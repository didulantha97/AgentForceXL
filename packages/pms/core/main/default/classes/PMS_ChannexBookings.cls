/**
 * Bookings from Channex (Booking.com, Expedia, Airbnb...), read from the booking revisions feed.
 *
 *   new / modified  one PMS reservation per OTA room (key: Channex booking ID + room number), created
 *                   through PMS_BookingService so a free room is assigned and room nights and inventory
 *                   are kept current. If no room is free the reservation is still saved, without a room,
 *                   and flagged, because an OTA booking cannot be refused. The OTA amount becomes the
 *                   booking total and the nightly OTA amounts become the room night rates.
 *   cancelled       every reservation of the booking is cancelled (OTA cancellations never get PMS fees).
 *
 * Guest details are saved before the revision is acknowledged (Channex removes them from its API once a
 * revision is acknowledged). A revision that fails is rolled back on its own, logged, and left
 * unacknowledged, so Channex keeps offering it and the next run retries.
 */
public without sharing class PMS_ChannexBookings {
  public static final Integer MAX_PER_RUN = 10;

  public class Outcome {
    public List<String> ackIds = new List<String>();
    public List<PMS_Channel_Log__c> logs = new List<PMS_Channel_Log__c>();
    public Boolean more = false;
  }

  /** Callout: unacknowledged revisions, oldest first. */
  public static List<Map<String, Object>> fetchFeed() {
    Map<String, Object> res = PMS_ChannexClient.get(
      '/booking_revisions/feed?order[inserted_at]=asc&pagination[limit]=' +
      MAX_PER_RUN
    );
    List<Map<String, Object>> out = new List<Map<String, Object>>();
    for (Object o : PMS_ChannexClient.asList(res.get('data'))) {
      Map<String, Object> item = PMS_ChannexClient.asMap(o);
      Map<String, Object> attrs = PMS_ChannexClient.asMap(
        item.get('attributes')
      );
      if (!attrs.containsKey('id') && item.containsKey('id')) {
        attrs.put('id', item.get('id'));
      }
      out.add(attrs);
    }
    return out;
  }

  /** DML only. Returns the revisions that may be acknowledged and the logs to save. */
  public static Outcome process(List<Map<String, Object>> revisions) {
    Outcome o = new Outcome();
    o.more = revisions.size() >= MAX_PER_RUN;
    Map<String, PMS_Site__c> sites = new Map<String, PMS_Site__c>();
    for (PMS_Site__c s : [
      SELECT
        Id,
        Name,
        Time_Zone__c,
        Check_In_Time__c,
        Check_Out_Time__c,
        Channex_Property_Id__c,
        Channex_Prices_Include_VAT__c
      FROM PMS_Site__c
      WHERE Channex_Property_Id__c != NULL
    ]) {
      sites.put(s.Channex_Property_Id__c.toLowerCase(), s);
    }
    Map<String, Id> roomTypes = new Map<String, Id>();
    for (PMS_Space_Type__c t : [
      SELECT Id, Channex_Room_Type_Id__c
      FROM PMS_Space_Type__c
      WHERE Channex_Room_Type_Id__c != NULL
    ]) {
      roomTypes.put(t.Channex_Room_Type_Id__c.toLowerCase(), t.Id);
    }
    Map<String, PMS_Channel_Mapping__c> plans = new Map<String, PMS_Channel_Mapping__c>();
    for (PMS_Channel_Mapping__c m : [
      SELECT
        Rate_Plan__c,
        Rate_Plan__r.Tax_Rate__c,
        Room_Type__c,
        Channex_Rate_Plan_Id__c
      FROM PMS_Channel_Mapping__c
      WHERE Channex_Rate_Plan_Id__c != NULL
    ]) {
      plans.put(m.Channex_Rate_Plan_Id__c.toLowerCase(), m);
    }
    for (Map<String, Object> rev : revisions) {
      String revId = PMS_ChannexClient.str(rev, 'id');
      Savepoint sp = Database.setSavepoint();
      try {
        PMS_Site__c site = sites.get(
          lower(PMS_ChannexClient.str(rev, 'property_id'))
        );
        if (site == null) {
          throw new PMS_Exception(
            'No site has Channex Property ID ' +
              PMS_ChannexClient.str(rev, 'property_id') +
              '.'
          );
        }
        PMS_Channel_Log__c log = apply(rev, site, roomTypes, plans);
        o.logs.add(log);
        o.ackIds.add(revId);
      } catch (Exception e) {
        Database.rollback(sp);
        o.logs.add(
          new PMS_Channel_Log__c(
            Direction__c = 'Inbound',
            Kind__c = 'Error',
            Status__c = 'Error',
            Revision_Id__c = revId,
            Message__c = ('Booking ' +
              PMS_ChannexClient.str(rev, 'ota_reservation_code') +
              ' not saved: ' +
              e.getMessage())
              .left(255),
            Details__c = JSON.serializePretty(redact(rev)).left(32000)
          )
        );
      }
    }
    return o;
  }

  private static PMS_Channel_Log__c apply(
    Map<String, Object> rev,
    PMS_Site__c site,
    Map<String, Id> roomTypes,
    Map<String, PMS_Channel_Mapping__c> plans
  ) {
    String status = PMS_ChannexClient.str(rev, 'status');
    String bookingId = PMS_ChannexClient.str(rev, 'booking_id');
    String revId = PMS_ChannexClient.str(rev, 'id');
    if (String.isBlank(bookingId)) {
      throw new PMS_Exception('The revision has no booking_id.');
    }
    List<PMS_Booking__c> existing = [
      SELECT
        Id,
        Name,
        Status__c,
        Channex_Room_Key__c,
        Space__c,
        Start__c,
        End__c
      FROM PMS_Booking__c
      WHERE Channex_Booking_Id__c = :bookingId
      ORDER BY Channex_Room_Key__c
    ];
    Map<String, PMS_Booking__c> byKey = new Map<String, PMS_Booking__c>();
    for (PMS_Booking__c b : existing) {
      byKey.put(b.Channex_Room_Key__c, b);
    }

    if (status == 'cancelled') {
      List<PMS_Booking__c> cancel = new List<PMS_Booking__c>();
      for (PMS_Booking__c b : existing) {
        if (
          b.Status__c != 'Cancelled' &&
          b.Status__c != 'Completed' &&
          b.Status__c != 'Active'
        ) {
          cancel.add(
            new PMS_Booking__c(
              Id = b.Id,
              Status__c = 'Cancelled',
              Channex_Revision_Id__c = revId
            )
          );
        }
      }
      withoutPolicyFees(cancel);
      return inbound(
        'Booking Cancelled',
        revId,
        site.Id,
        existing.isEmpty() ? null : existing[0].Id,
        'Cancelled by ' +
          PMS_ChannexClient.str(rev, 'ota_name') +
          ' (' +
          PMS_ChannexClient.str(rev, 'ota_reservation_code') +
          '): ' +
          cancel.size() +
          ' reservation(s).' +
          (existing.isEmpty() ? ' It was never in the PMS.' : '')
      );
    }

    Contact guest = guestFor(rev);
    List<Object> rooms = PMS_ChannexClient.asList(rev.get('rooms'));
    if (rooms.isEmpty()) {
      throw new PMS_Exception('The revision has no rooms.');
    }
    List<String> notes = new List<String>();
    Id firstBooking;
    Set<String> seen = new Set<String>();
    for (Integer i = 0; i < rooms.size(); i++) {
      Map<String, Object> room = PMS_ChannexClient.asMap(rooms[i]);
      String key = bookingId + '#' + (i + 1);
      seen.add(key);
      Id typeId = roomTypes.get(
        lower(PMS_ChannexClient.str(room, 'room_type_id'))
      );
      if (typeId == null) {
        throw new PMS_Exception(
          'Room ' +
            (i + 1) +
            ': Channex room type ' +
            PMS_ChannexClient.str(room, 'room_type_id') +
            ' is not mapped to a PMS room type.'
        );
      }
      PMS_Channel_Mapping__c plan = plans.get(
        lower(PMS_ChannexClient.str(room, 'rate_plan_id'))
      );
      Date arrive = Date.valueOf(
        firstNonBlank(
          PMS_ChannexClient.str(room, 'checkin_date'),
          PMS_ChannexClient.str(rev, 'arrival_date')
        )
      );
      Date depart = Date.valueOf(
        firstNonBlank(
          PMS_ChannexClient.str(room, 'checkout_date'),
          PMS_ChannexClient.str(rev, 'departure_date')
        )
      );
      Map<String, Object> occ = PMS_ChannexClient.asMap(room.get('occupancy'));
      Integer adults = toInt(occ.get('adults'), 1);
      Integer children =
        toInt(occ.get('children'), 0) + toInt(occ.get('infants'), 0);
      Decimal amount = toDecimal(room.get('amount'));
      PMS_Booking__c b = byKey.get(key);
      if (b == null) {
        b = create(
          site,
          typeId,
          plan,
          guest,
          arrive,
          depart,
          adults,
          children,
          PMS_ChannexClient.str(rev, 'notes'),
          notes,
          i + 1
        );
      } else {
        b = modify(b, site, arrive, depart, adults, children, notes, i + 1);
      }
      update new PMS_Booking__c(
        Id = b.Id,
        Channel__c = 'OTA',
        Channex_Booking_Id__c = bookingId,
        Channex_Room_Key__c = key,
        Channex_Revision_Id__c = revId,
        OTA_Name__c = cut(PMS_ChannexClient.str(rev, 'ota_name'), 60),
        OTA_Reservation_Code__c = cut(
          PMS_ChannexClient.str(rev, 'ota_reservation_code'),
          80
        ),
        Total_Amount__c = amount,
        Rate_Amount__c = amount == null ||
          arrive.daysBetween(depart) <= 0
          ? null
          : (amount / arrive.daysBetween(depart)).setScale(2),
        Guarantee__c = PMS_ChannexClient.str(rev, 'payment_collect') == 'ota'
          ? 'Prepaid'
          : 'None',
        Account__c = guest.AccountId,
        Primary_Contact__c = guest.Id
      );
      applyNightlyAmounts(
        b.Id,
        PMS_ChannexClient.asMap(room.get('days')),
        site,
        plan
      );
      if (firstBooking == null) {
        firstBooking = b.Id;
      }
    }
    List<PMS_Booking__c> dropped = new List<PMS_Booking__c>();
    for (PMS_Booking__c b : existing) {
      if (
        !seen.contains(b.Channex_Room_Key__c) &&
        b.Status__c != 'Cancelled' &&
        b.Status__c != 'Active' &&
        b.Status__c != 'Completed'
      ) {
        dropped.add(
          new PMS_Booking__c(
            Id = b.Id,
            Status__c = 'Cancelled',
            Channex_Revision_Id__c = revId
          )
        );
      }
    }
    withoutPolicyFees(dropped);
    if (!dropped.isEmpty()) {
      notes.add(dropped.size() + ' room(s) removed by the OTA were cancelled.');
    }
    String kind = existing.isEmpty() ? 'Booking New' : 'Booking Modified';
    return inbound(
      kind,
      revId,
      site.Id,
      firstBooking,
      PMS_ChannexClient.str(rev, 'ota_name') +
        ' ' +
        PMS_ChannexClient.str(rev, 'ota_reservation_code') +
        ': ' +
        rooms.size() +
        ' room(s), ' +
        PMS_ChannexClient.str(rev, 'arrival_date') +
        ' to ' +
        PMS_ChannexClient.str(rev, 'departure_date') +
        '. ' +
        String.join(notes, ' ')
    );
  }

  private static PMS_Booking__c create(
    PMS_Site__c site,
    Id typeId,
    PMS_Channel_Mapping__c plan,
    Contact guest,
    Date arrive,
    Date depart,
    Integer adults,
    Integer children,
    String otaNotes,
    List<String> notes,
    Integer roomNo
  ) {
    PMS_BookingService.BookingRequest req = new PMS_BookingService.BookingRequest();
    req.module = PMS_ModuleConfig.HOTEL;
    req.siteId = site.Id;
    req.spaceTypeId = typeId;
    req.ratePlanId = plan == null ? null : plan.Rate_Plan__c;
    req.accountId = guest.AccountId;
    req.contactId = guest.Id;
    req.startDate = arrive;
    req.endDate = depart;
    req.adults = adults;
    req.children = children;
    req.channel = 'OTA';
    req.status = 'Confirmed';
    req.specialRequests = cut(otaNotes, 32000);
    Savepoint sp = Database.setSavepoint();
    try {
      return PMS_BookingService.createBooking(req);
    } catch (PMS_Exception e) {
      if (e.getMessage() == null || !e.getMessage().contains('free')) {
        throw e;
      }
      Database.rollback(sp);
    }
    // Overbooked: keep the OTA booking without a room so staff can sort it out.
    PMS_Booking__c b = new PMS_Booking__c(
      RecordTypeId = PMS_ModuleConfig.bookingRecordTypeId(
        PMS_ModuleConfig.HOTEL
      ),
      Site__c = site.Id,
      Room_Type_Requested__c = typeId,
      Rate_Plan__c = plan == null ? null : plan.Rate_Plan__c,
      Account__c = guest.AccountId,
      Primary_Contact__c = guest.Id,
      Start__c = PMS_DateUtil.toDatetime(
        arrive,
        site.Check_In_Time__c == null
          ? Time.newInstance(15, 0, 0, 0)
          : site.Check_In_Time__c,
        site.Time_Zone__c
      ),
      End__c = PMS_DateUtil.toDatetime(
        depart,
        site.Check_Out_Time__c == null
          ? Time.newInstance(11, 0, 0, 0)
          : site.Check_Out_Time__c,
        site.Time_Zone__c
      ),
      Status__c = 'Confirmed',
      Channel__c = 'OTA',
      Adults__c = adults,
      Children__c = children,
      Special_Requests__c = 'OVERBOOKED: no room of this type was free when the OTA booking arrived. Assign a room.' +
        (String.isBlank(otaNotes) ? '' : '\n' + otaNotes)
    );
    insert b;
    notes.add(
      'Room ' +
        roomNo +
        ' is OVERBOOKED: no free room of the type, saved without a room.'
    );
    return b;
  }

  private static PMS_Booking__c modify(
    PMS_Booking__c b,
    PMS_Site__c site,
    Date arrive,
    Date depart,
    Integer adults,
    Integer children,
    List<String> notes,
    Integer roomNo
  ) {
    Datetime s = PMS_DateUtil.toDatetime(
      arrive,
      site.Check_In_Time__c == null
        ? Time.newInstance(15, 0, 0, 0)
        : site.Check_In_Time__c,
      site.Time_Zone__c
    );
    Datetime e = PMS_DateUtil.toDatetime(
      depart,
      site.Check_Out_Time__c == null
        ? Time.newInstance(11, 0, 0, 0)
        : site.Check_Out_Time__c,
      site.Time_Zone__c
    );
    PMS_Booking__c u = new PMS_Booking__c(
      Id = b.Id,
      Start__c = s,
      End__c = e,
      Adults__c = adults,
      Children__c = children
    );
    if (b.Status__c == 'Cancelled') {
      u.Status__c = 'Confirmed';
      notes.add('Room ' + roomNo + ' was reinstated.');
    }
    if (
      b.Space__c != null &&
      (s != b.Start__c ||
      e != b.End__c) &&
      !PMS_AvailabilityService.isSpaceAvailable(b.Space__c, s, e, b.Id)
    ) {
      u.Space__c = null;
      notes.add(
        'Room ' +
          roomNo +
          ': the assigned room is not free for the new dates; assign another room.'
      );
    }
    update u;
    return b;
  }

  /** OTA nightly amounts become the room night rates (net of VAT when the site's prices include VAT). */
  private static void applyNightlyAmounts(
    Id bookingId,
    Map<String, Object> days,
    PMS_Site__c site,
    PMS_Channel_Mapping__c plan
  ) {
    if (days.isEmpty()) {
      return;
    }
    Decimal tax = plan != null &&
      plan.Rate_Plan__r != null &&
      plan.Rate_Plan__r.Tax_Rate__c != null
      ? plan.Rate_Plan__r.Tax_Rate__c
      : PMS_ModuleConfig.defaultTaxRate(PMS_ModuleConfig.HOTEL);
    Decimal divisor = site.Channex_Prices_Include_VAT__c == true
      ? 1 + (tax == null ? 0 : tax) / 100
      : 1;
    List<PMS_Room_Night__c> nights = [
      SELECT Id, Stay_Date__c, Status__c
      FROM PMS_Room_Night__c
      WHERE Reservation__c = :bookingId AND Status__c != 'Posted'
    ];
    for (PMS_Room_Night__c n : nights) {
      Decimal gross = toDecimal(days.get(String.valueOf(n.Stay_Date__c)));
      if (gross != null) {
        n.Rate__c = (gross / divisor).setScale(2, RoundingMode.HALF_UP);
      }
    }
    if (!nights.isEmpty()) {
      update nights;
    }
  }

  /** Finds the guest by email, or creates an account and contact. */
  @TestVisible
  private static Contact guestFor(Map<String, Object> rev) {
    Map<String, Object> c = PMS_ChannexClient.asMap(rev.get('customer'));
    String first = cut(PMS_ChannexClient.str(c, 'name'), 40);
    String last = cut(PMS_ChannexClient.str(c, 'surname'), 80);
    String mail = PMS_ChannexClient.str(c, 'mail');
    String phone = cut(PMS_ChannexClient.str(c, 'phone'), 40);
    if (String.isNotBlank(mail)) {
      List<Contact> found = [
        SELECT Id, AccountId, Phone
        FROM Contact
        WHERE Email = :mail AND AccountId != NULL
        ORDER BY CreatedDate
        LIMIT 1
      ];
      if (!found.isEmpty()) {
        if (String.isBlank(found[0].Phone) && String.isNotBlank(phone)) {
          update new Contact(Id = found[0].Id, Phone = phone);
        }
        return found[0];
      }
    }
    String display = String.join(
        new List<String>{
          first == null ? '' : first,
          last == null ? '' : last
        },
        ' '
      )
      .trim();
    if (String.isBlank(display)) {
      display =
        'OTA guest ' + PMS_ChannexClient.str(rev, 'ota_reservation_code');
    }
    Account a = new Account(Name = cut(display, 255), Phone = phone);
    insert a;
    Contact ct = new Contact(
      AccountId = a.Id,
      FirstName = first,
      LastName = String.isBlank(last)
        ? (String.isBlank(first) ? 'Guest' : first)
        : last,
      Email = String.isBlank(mail) ? null : mail,
      Phone = phone
    );
    insert ct;
    return ct;
  }

  private static void withoutPolicyFees(List<PMS_Booking__c> rows) {
    if (rows.isEmpty()) {
      return;
    }
    Boolean before = PMS_TriggerBypass.policyFees;
    PMS_TriggerBypass.policyFees = true; // the OTA applies its own cancellation terms
    try {
      update rows;
    } finally {
      PMS_TriggerBypass.policyFees = before;
    }
  }

  /** Callouts: acknowledges processed revisions. Returns log rows (no DML here). */
  public static List<PMS_Channel_Log__c> acknowledge(List<String> revisionIds) {
    List<PMS_Channel_Log__c> logs = new List<PMS_Channel_Log__c>();
    for (String id : revisionIds) {
      try {
        PMS_ChannexClient.post('/booking_revisions/' + id + '/ack', null);
      } catch (Exception e) {
        logs.add(
          new PMS_Channel_Log__c(
            Direction__c = 'Inbound',
            Kind__c = 'Acknowledge',
            Status__c = 'Error',
            Revision_Id__c = id,
            Message__c = ('Acknowledge failed: ' + e.getMessage()).left(255)
          )
        );
      }
    }
    return logs;
  }

  // ---------------------------------------------------------------- helpers

  private static PMS_Channel_Log__c inbound(
    String kind,
    String revId,
    Id siteId,
    Id bookingId,
    String message
  ) {
    return new PMS_Channel_Log__c(
      Direction__c = 'Inbound',
      Kind__c = kind,
      Status__c = message.contains('OVERBOOKED') || message.contains('not free')
        ? 'Warning'
        : 'Success',
      Revision_Id__c = revId,
      Site__c = siteId,
      Booking__c = bookingId,
      Message__c = message.left(255)
    );
  }

  /** Keeps guest contact details out of error logs. */
  private static Map<String, Object> redact(Map<String, Object> rev) {
    Map<String, Object> copy = rev.clone();
    copy.remove('customer');
    copy.remove('guarantee');
    copy.remove('raw_message');
    return copy;
  }

  private static String lower(String s) {
    return s == null ? null : s.toLowerCase();
  }

  private static String firstNonBlank(String a, String b) {
    return String.isNotBlank(a) ? a : b;
  }

  private static Integer toInt(Object o, Integer fallback) {
    if (o == null) {
      return fallback;
    }
    try {
      return Integer.valueOf(String.valueOf(o));
    } catch (Exception e) {
      return fallback;
    }
  }

  private static Decimal toDecimal(Object o) {
    if (o == null) {
      return null;
    }
    try {
      return Decimal.valueOf(String.valueOf(o));
    } catch (Exception e) {
      return null;
    }
  }

  private static String cut(String s, Integer max) {
    return s == null ? null : s.left(max);
  }
}
