/**
 * Guest 360 stats: recomputes the read-only PMS_* statistics on Contact.
 *
 * Guest's bookings = bookings where the guest is Primary_Contact__c UNION bookings where the guest is on
 * PMS_Booking_Party__c.Contact__c; each booking counts once per guest.
 *  - Total stays / lifetime nights / first stay / last stay: bookings with Status Confirmed, Active or Completed
 *    whose departure (End__c, local date) is before today, so a stay departing today counts from tomorrow's run.
 *    Nights are computed here from local start / end dates (Nights__c is a GMT-based formula and can be off by one).
 *  - Next arrival: earliest Start__c on or after today on a Tentative (a live hold: the night audit treats it as an
 *    expected arrival), Confirmed or Active booking. Inquiry, Cancelled and No Show never count.
 *  - Revenue: net (ex VAT) amount of non-void charges on the guest's own bookings (Primary_Contact__c only, so a
 *    party member never double counts), whatever the booking status, so cancellation / no-show fees count.
 *    Room Night and Rent = room revenue (ROOM_CHARGE_TYPES); levies and pass-through costs are excluded
 *    (NON_REVENUE_CHARGE_TYPES); everything else = extras.
 *    Single currency, no conversion.
 *
 * Row math (per call, 50,000 query-row limit): booking rows = qualifying bookings of the contacts as primary plus
 * qualifying party rows; revenue = at most 2 aggregate rows per contact. The batch passes at most 100 contacts, so
 * the limit holds up to an average of ~250 qualifying bookings per contact.
 *
 * without sharing: the stats fields are read-only for users, and every guest must be counted regardless of the
 * running user's record visibility (nightly job / backfill). Only the eight PMS_* stats fields on Contact are
 * written; nothing is returned to a caller, so no data is exposed. Documented for security review.
 */
public without sharing class PMS_GuestStatsService {
  public static final List<String> COMPLETED_STATUSES = new List<String>{
    'Confirmed',
    'Active',
    'Completed'
  };
  @TestVisible
  private static final List<String> ARRIVAL_STATUSES = new List<String>{
    'Tentative',
    'Confirmed',
    'Active'
  };
  // Accommodation revenue: hotel room nights and long-stay rent.
  @TestVisible
  private static final List<String> ROOM_CHARGE_TYPES = new List<String>{
    'Room Night',
    'Rent'
  };
  // Levies and pass-through costs recharged at cost: not revenue.
  @TestVisible
  private static final List<String> NON_REVENUE_CHARGE_TYPES = new List<String>{
    'City Tax',
    'Utilities',
    'Service Charge',
    'Expense'
  };
  private static final String VOID_STATUS = 'Void';

  private class Stats {
    Integer stays = 0;
    Decimal nights = 0;
    Decimal room = 0;
    Decimal extras = 0;
    Date firstStay;
    Date lastStay;
    Date nextArrival;
    Set<Id> seen = new Set<Id>();
  }

  public static void recalc(Set<Id> contactIds) {
    recalcWithErrors(contactIds);
  }

  /** Same as recalc; returns one message per Contact that could not be saved (empty when all saved). */
  public static List<String> recalcWithErrors(Set<Id> contactIds) {
    List<String> errors = new List<String>();
    if (contactIds == null || contactIds.isEmpty()) {
      return errors;
    }
    Set<Id> ids = new Set<Id>(contactIds);
    ids.remove(null);
    if (ids.isEmpty()) {
      return errors;
    }
    Map<Id, Stats> byContact = new Map<Id, Stats>();
    for (Id cId : ids) {
      byContact.put(cId, new Stats());
    }
    Datetime todayStart = Datetime.newInstance(
      Date.today(),
      Time.newInstance(0, 0, 0, 0)
    );

    // Own bookings (rows, de-duplicated per booking, aggregated in memory)
    for (PMS_Booking__c b : [
      SELECT Id, Primary_Contact__c, Status__c, Start__c, End__c
      FROM PMS_Booking__c
      WHERE
        Primary_Contact__c IN :ids
        AND ((Status__c IN :COMPLETED_STATUSES
        AND End__c < :todayStart)
        OR (Status__c IN :ARRIVAL_STATUSES
        AND Start__c >= :todayStart))
    ]) {
      addBooking(
        byContact.get(b.Primary_Contact__c),
        b.Id,
        b.Status__c,
        b.Start__c,
        b.End__c,
        todayStart
      );
    }
    // Party member bookings (a booking where the guest is also primary is already counted above)
    for (PMS_Booking_Party__c p : [
      SELECT
        Contact__c,
        Booking__c,
        Booking__r.Primary_Contact__c,
        Booking__r.Status__c,
        Booking__r.Start__c,
        Booking__r.End__c
      FROM PMS_Booking_Party__c
      WHERE
        Contact__c IN :ids
        AND Booking__c != NULL
        AND ((Booking__r.Status__c IN :COMPLETED_STATUSES
        AND Booking__r.End__c < :todayStart)
        OR (Booking__r.Status__c IN :ARRIVAL_STATUSES
        AND Booking__r.Start__c >= :todayStart))
    ]) {
      if (p.Booking__r.Primary_Contact__c == p.Contact__c) {
        continue;
      }
      addBooking(
        byContact.get(p.Contact__c),
        p.Booking__c,
        p.Booking__r.Status__c,
        p.Booking__r.Start__c,
        p.Booking__r.End__c,
        todayStart
      );
    }
    // Revenue: net amount (ex VAT) of non-void charges, attributed to the booking's primary contact.
    // Two grouped queries, so at most one row per contact each.
    for (AggregateResult ar : [
      SELECT Booking__r.Primary_Contact__c c, SUM(Net_Amount__c) amt
      FROM PMS_Charge__c
      WHERE
        Booking__r.Primary_Contact__c IN :ids
        AND Status__c != :VOID_STATUS
        AND Charge_Type__c IN :ROOM_CHARGE_TYPES
      GROUP BY Booking__r.Primary_Contact__c
    ]) {
      byContact.get((Id) ar.get('c')).room = toDecimal(ar.get('amt'));
    }
    List<String> notExtras = new List<String>(NON_REVENUE_CHARGE_TYPES);
    notExtras.addAll(ROOM_CHARGE_TYPES);
    for (AggregateResult ar : [
      SELECT Booking__r.Primary_Contact__c c, SUM(Net_Amount__c) amt
      FROM PMS_Charge__c
      WHERE
        Booking__r.Primary_Contact__c IN :ids
        AND Status__c != :VOID_STATUS
        AND Charge_Type__c NOT IN :notExtras
      GROUP BY Booking__r.Primary_Contact__c
    ]) {
      byContact.get((Id) ar.get('c')).extras = toDecimal(ar.get('amt'));
    }

    Datetime now = Datetime.now();
    List<Contact> updates = new List<Contact>();
    for (Id cId : byContact.keySet()) {
      Stats s = byContact.get(cId);
      updates.add(
        new Contact(
          Id = cId,
          PMS_Total_Stays__c = s.stays,
          PMS_Lifetime_Nights__c = s.nights,
          PMS_Room_Revenue__c = s.room,
          PMS_Extras_Revenue__c = s.extras,
          PMS_First_Stay__c = s.firstStay,
          PMS_Last_Stay__c = s.lastStay,
          PMS_Next_Arrival__c = s.nextArrival,
          PMS_Stats_Refreshed__c = now
        )
      );
    }
    List<Database.SaveResult> results = Database.update(
      updates,
      false,
      AccessLevel.SYSTEM_MODE
    );
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        String msg =
          'Contact ' +
          updates[i].Id +
          ': ' +
          results[i].getErrors()[0].getMessage();
        System.debug(
          LoggingLevel.ERROR,
          'PMS guest stats not saved for ' + msg
        );
        errors.add(msg);
      }
    }
    return errors;
  }

  private static void addBooking(
    Stats s,
    Id bookingId,
    String status,
    Datetime startDt,
    Datetime endDt,
    Datetime todayStart
  ) {
    if (!s.seen.add(bookingId)) {
      return; // duplicate party row
    }
    if (
      COMPLETED_STATUSES.contains(status) &&
      endDt != null &&
      endDt < todayStart
    ) {
      Date startDate = startDt == null ? null : startDt.date();
      Date endDate = endDt.date();
      s.stays++;
      if (startDate != null) {
        s.nights += Math.max(startDate.daysBetween(endDate), 0);
        s.firstStay = earlier(s.firstStay, startDate);
      }
      s.lastStay = later(s.lastStay, endDate);
    }
    if (
      ARRIVAL_STATUSES.contains(status) &&
      startDt != null &&
      startDt >= todayStart
    ) {
      s.nextArrival = earlier(s.nextArrival, startDt.date());
    }
  }

  private static Date earlier(Date a, Date b) {
    return a == null ? b : (b == null || a <= b ? a : b);
  }

  private static Date later(Date a, Date b) {
    return a == null ? b : (b == null || a >= b ? a : b);
  }

  private static Decimal toDecimal(Object o) {
    return o == null ? 0 : (Decimal) o;
  }
}
