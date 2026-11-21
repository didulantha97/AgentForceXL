/**
 * Creates and runs the lifecycle of bookings for every module:
 * Lease (Property), Reservation (Hotel), Allocation (Project), Appointment (Practice).
 * Hotel reservations also get one Room Night per night and keep Inventory Days current.
 */
@NamespaceAccessible
public inherited sharing class PMS_BookingService {
  @NamespaceAccessible
  public static final Set<String> INACTIVE_NIGHT_STATUSES = new Set<String>{
    'Cancelled',
    'No Show'
  };
  private static final Integer MAX_INVENTORY_DAYS = 400;

  @NamespaceAccessible
  public class BookingRequest {
    @NamespaceAccessible
    public BookingRequest() {
    }

    @NamespaceAccessible
    public String module;
    @NamespaceAccessible
    public Id siteId;
    @NamespaceAccessible
    public Id spaceId;
    @NamespaceAccessible
    public Id spaceTypeId;
    @NamespaceAccessible
    public Id accountId;
    @NamespaceAccessible
    public Id contactId;
    @NamespaceAccessible
    public Date startDate;
    @NamespaceAccessible
    public Date endDate;
    @NamespaceAccessible
    public Datetime startDatetime;
    @NamespaceAccessible
    public Datetime endDatetime;
    @NamespaceAccessible
    public Integer adults;
    @NamespaceAccessible
    public Integer children;
    @NamespaceAccessible
    public String channel;
    @NamespaceAccessible
    public String status;
    @NamespaceAccessible
    public Id ratePlanId;
    @NamespaceAccessible
    public Id serviceId;
    @NamespaceAccessible
    public Id practitionerId;
    @NamespaceAccessible
    public Id matterId;
    @NamespaceAccessible
    public Id projectId;
    @NamespaceAccessible
    public Id resourceId;
    @NamespaceAccessible
    public Decimal hoursPerWeek;
    @NamespaceAccessible
    public String appointmentMode;
    @NamespaceAccessible
    public String specialRequests;
  }

  // ---------------------------------------------------------------- create

  @NamespaceAccessible
  public static PMS_Booking__c createBooking(BookingRequest req) {
    if (req == null || String.isBlank(req.module)) {
      throw new PMS_Exception('Choose a module for the booking.');
    }
    if (!PMS_ModuleConfig.isEnabled(req.module)) {
      throw new PMS_Exception('The ' + req.module + ' module is switched off.');
    }
    PMS_Site__c site = loadSite(req.siteId, req.spaceId);
    Datetime[] window = resolveWindow(req, site);
    Integer guests =
      (req.adults == null ? 0 : req.adults) +
      (req.children == null ? 0 : req.children);

    Id spaceId = req.spaceId;
    if (
      spaceId == null &&
      req.spaceTypeId != null &&
      req.module != PMS_ModuleConfig.PROJECT
    ) {
      List<PMS_Space__c> free = PMS_AvailabilityService.findAvailableSpaces(
        site.Id,
        req.spaceTypeId,
        window[0],
        window[1],
        guests
      );
      if (free.isEmpty()) {
        throw new PMS_Exception(
          'Nothing of that type is free for those dates.'
        );
      }
      spaceId = free[0].Id;
    } else if (
      spaceId != null &&
      !PMS_AvailabilityService.isSpaceAvailable(
        spaceId,
        window[0],
        window[1],
        null
      )
    ) {
      throw new PMS_Exception('That space is already booked for those dates.');
    }

    PMS_PricingService.QuoteRequest qr = new PMS_PricingService.QuoteRequest();
    qr.module = req.module;
    qr.ratePlanId = req.ratePlanId;
    qr.spaceTypeId = req.spaceTypeId;
    qr.spaceId = spaceId;
    qr.serviceId = req.serviceId;
    qr.startDate = PMS_DateUtil.toLocalDate(window[0], site.Time_Zone__c);
    qr.endDate = PMS_DateUtil.toLocalDate(window[1], site.Time_Zone__c);
    if (req.module == PMS_ModuleConfig.PRACTICE) {
      qr.hours =
        Decimal.valueOf((window[1].getTime() - window[0].getTime()) / 60000) /
        60;
    }
    PMS_PricingService.Quote q = PMS_PricingService.quote(qr);

    PMS_Booking__c b = new PMS_Booking__c(
      RecordTypeId = PMS_ModuleConfig.bookingRecordTypeId(req.module),
      Site__c = site.Id,
      Space__c = spaceId,
      Room_Type_Requested__c = req.spaceTypeId,
      Account__c = req.accountId,
      Primary_Contact__c = req.contactId,
      Start__c = window[0],
      End__c = window[1],
      Status__c = String.isBlank(req.status) ? 'Confirmed' : req.status,
      Channel__c = String.isBlank(req.channel) ? 'Direct' : req.channel,
      Adults__c = req.adults,
      Children__c = req.children,
      Rate_Plan__c = q.ratePlanId,
      Rate_Amount__c = q.unitPrice,
      Total_Amount__c = q.gross,
      Service__c = req.serviceId,
      Practitioner__c = req.practitionerId,
      Matter__c = req.matterId,
      Project__c = req.projectId,
      Resource__c = req.resourceId,
      Hours_Per_Week__c = req.hoursPerWeek,
      Appointment_Mode__c = req.appointmentMode,
      Special_Requests__c = req.specialRequests
    );
    if (req.module == PMS_ModuleConfig.PROPERTY) {
      b.Rent_Frequency__c = 'Monthly';
    }
    insert b;
    if (
      req.module == PMS_ModuleConfig.PROPERTY &&
      q.unitPrice != null &&
      q.unitPrice > 0
    ) {
      // A lease gets its monthly rent schedule straight away, so the rent run picks it up.
      insert new PMS_Lease_Charge_Schedule__c(
        Lease__c = b.Id,
        Charge_Type__c = 'Rent',
        Amount__c = q.unitPrice,
        Frequency__c = 'Monthly',
        Start_Date__c = qr.startDate,
        End_Date__c = qr.endDate == null ? null : qr.endDate.addDays(-1),
        Next_Run_Date__c = qr.startDate,
        Active__c = true
      );
    }
    return b;
  }

  @TestVisible
  private static PMS_Site__c loadSite(Id siteId, Id spaceId) {
    Id resolved = siteId;
    if (resolved == null && spaceId != null) {
      resolved = [SELECT Site__c FROM PMS_Space__c WHERE Id = :spaceId].Site__c;
    }
    if (resolved == null) {
      throw new PMS_Exception('Choose a site for the booking.');
    }
    return [
      SELECT
        Id,
        Name,
        Module__c,
        Time_Zone__c,
        Check_In_Time__c,
        Check_Out_Time__c,
        Currency_Code__c
      FROM PMS_Site__c
      WHERE Id = :resolved
    ];
  }

  /** Start and end instants: hotel uses check-in/out times, leases start of day, appointments use service length. */
  @TestVisible
  private static Datetime[] resolveWindow(
    BookingRequest req,
    PMS_Site__c site
  ) {
    Datetime s = req.startDatetime;
    Datetime e = req.endDatetime;
    if (s == null && req.startDate != null) {
      Time t = req.module == PMS_ModuleConfig.HOTEL
        ? defaultTime(site.Check_In_Time__c, 15)
        : Time.newInstance(0, 0, 0, 0);
      s = PMS_DateUtil.toDatetime(req.startDate, t, site.Time_Zone__c);
    }
    if (e == null && req.endDate != null) {
      Time t = req.module == PMS_ModuleConfig.HOTEL
        ? defaultTime(site.Check_Out_Time__c, 11)
        : Time.newInstance(0, 0, 0, 0);
      e = PMS_DateUtil.toDatetime(req.endDate, t, site.Time_Zone__c);
    }
    if (e == null && s != null && req.serviceId != null) {
      PMS_Service__c svc = [
        SELECT Duration_Minutes__c
        FROM PMS_Service__c
        WHERE Id = :req.serviceId
      ];
      Integer minutes = svc.Duration_Minutes__c == null
        ? 60
        : svc.Duration_Minutes__c.intValue();
      e = s.addMinutes(minutes);
    }
    if (s == null || e == null) {
      throw new PMS_Exception('Give both a start and an end.');
    }
    if (e <= s) {
      throw new PMS_Exception('The end must be after the start.');
    }
    return new List<Datetime>{ s, e };
  }

  private static Time defaultTime(Time t, Integer hour) {
    return t == null ? Time.newInstance(hour, 0, 0, 0) : t;
  }

  // ---------------------------------------------------------------- front desk

  @NamespaceAccessible
  public static void checkIn(Id bookingId, Id roomId) {
    PMS_Booking__c b = [
      SELECT Id, Status__c, Space__c, Start__c, End__c
      FROM PMS_Booking__c
      WHERE Id = :bookingId
      FOR UPDATE
    ];
    if (b.Status__c != 'Confirmed' && b.Status__c != 'Tentative') {
      throw new PMS_Exception(
        'Only confirmed bookings can be checked in (this one is ' +
          b.Status__c +
          ').'
      );
    }
    Id room = roomId == null ? b.Space__c : roomId;
    if (room == null) {
      throw new PMS_Exception('Assign a room before check-in.');
    }
    if (
      room != b.Space__c &&
      !PMS_AvailabilityService.isSpaceAvailable(
        room,
        b.Start__c,
        b.End__c,
        b.Id
      )
    ) {
      throw new PMS_Exception('That room is not free for this stay.');
    }
    b.Space__c = room;
    b.Status__c = 'Active';
    update b;
    update new PMS_Space__c(Id = room, Operational_Status__c = 'Occupied');
  }

  @NamespaceAccessible
  public static void checkOut(Id bookingId) {
    PMS_Booking__c b = [
      SELECT
        Id,
        Name,
        Status__c,
        Space__c,
        Space__r.Name,
        Site__c,
        Start__c,
        End__c
      FROM PMS_Booking__c
      WHERE Id = :bookingId
      FOR UPDATE
    ];
    if (b.Status__c != 'Active') {
      throw new PMS_Exception('Only in-house bookings can be checked out.');
    }
    Datetime now = Datetime.now();
    if (now > b.Start__c && now < b.End__c) {
      b.End__c = now; // early departure: remaining nights are released and never charged
    }
    b.Status__c = 'Completed';
    update b;
    Id bookingRef = b.Id;
    PMS_BillingService.invoicePendingCharges(
      Database.query(
        PMS_BillingService.pendingChargeQuery() +
        ' AND Booking__c = :bookingRef'
      ),
      Date.today()
    );
    if (b.Space__c != null) {
      update new PMS_Space__c(Id = b.Space__c, Operational_Status__c = 'Dirty');
      insert new Case(
        Subject = 'Departure clean - ' + b.Space__r.Name,
        Origin = 'Web',
        Priority = 'Medium',
        PMS_Module__c = PMS_ModuleConfig.HOTEL,
        PMS_Site__c = b.Site__c,
        PMS_Space__c = b.Space__c,
        PMS_Booking__c = b.Id,
        Description = 'Created automatically at check-out of ' + b.Name + '.'
      );
    }
  }

  @NamespaceAccessible
  public static void cancel(Id bookingId, String reason) {
    PMS_Booking__c b = [
      SELECT Id, Status__c, Special_Requests__c
      FROM PMS_Booking__c
      WHERE Id = :bookingId
      FOR UPDATE
    ];
    if (b.Status__c == 'Completed' || b.Status__c == 'Active') {
      throw new PMS_Exception(
        'Bookings that have started cannot be cancelled; check out or end them instead.'
      );
    }
    b.Status__c = 'Cancelled';
    if (String.isNotBlank(reason)) {
      b.Special_Requests__c =
        (String.isBlank(b.Special_Requests__c)
          ? ''
          : b.Special_Requests__c + '\n') +
        'Cancelled: ' +
        reason;
    }
    update b;
  }

  /** Moves a booking to another space and/or start date, keeping its length. Used by the room grid. */
  @NamespaceAccessible
  public static void move(Id bookingId, Id newSpaceId, Date newStartDate) {
    PMS_Booking__c b = [
      SELECT Id, Space__c, Start__c, End__c, Site__r.Time_Zone__c, Status__c
      FROM PMS_Booking__c
      WHERE Id = :bookingId
      FOR UPDATE
    ];
    if (b.Status__c == 'Completed' || b.Status__c == 'Cancelled') {
      throw new PMS_Exception(
        'Finished or cancelled bookings cannot be moved.'
      );
    }
    Datetime s = b.Start__c;
    Datetime e = b.End__c;
    if (newStartDate != null) {
      String tz = b.Site__r.Time_Zone__c;
      Integer shift = PMS_DateUtil.toLocalDate(b.Start__c, tz)
        .daysBetween(newStartDate);
      s = s.addDays(shift);
      e = e.addDays(shift);
    }
    Id space = newSpaceId == null ? b.Space__c : newSpaceId;
    if (!PMS_AvailabilityService.isSpaceAvailable(space, s, e, b.Id)) {
      throw new PMS_Exception('The target space is not free for those dates.');
    }
    b.Space__c = space;
    b.Start__c = s;
    b.End__c = e;
    update b;
  }

  // ---------------------------------------------------------------- hotel: room nights + inventory

  @NamespaceAccessible
  public static void syncRoomNights(List<PMS_Booking__c> reservations) {
    if (reservations.isEmpty()) {
      return;
    }
    Map<Id, PMS_Booking__c> byId = new Map<Id, PMS_Booking__c>(
      [
        SELECT
          Id,
          Status__c,
          Start__c,
          End__c,
          Space__c,
          Space__r.Space_Type__c,
          Room_Type_Requested__c,
          Rate_Plan__c,
          Rate_Amount__c,
          Site__r.Time_Zone__c,
          (SELECT Id, Status__c, Stay_Date__c FROM Room_Nights__r)
        FROM PMS_Booking__c
        WHERE Id IN :reservations
      ]
    );
    List<PMS_Room_Night__c> toDelete = new List<PMS_Room_Night__c>();
    List<PMS_Room_Night__c> toInsert = new List<PMS_Room_Night__c>();
    for (PMS_Booking__c b : byId.values()) {
      Set<Date> postedDates = new Set<Date>();
      for (PMS_Room_Night__c rn : b.Room_Nights__r) {
        if (rn.Status__c == 'Posted') {
          postedDates.add(rn.Stay_Date__c); // already charged: never touched again
        } else {
          toDelete.add(rn);
        }
      }
      if (b.Start__c == null || b.End__c == null) {
        continue;
      }
      Id typeId = b.Room_Type_Requested__c != null
        ? b.Room_Type_Requested__c
        : b.Space__r?.Space_Type__c;
      String tz = b.Site__r.Time_Zone__c;
      Date startDate = PMS_DateUtil.toLocalDate(b.Start__c, tz);
      Date endDate = PMS_DateUtil.toLocalDate(b.End__c, tz);
      Map<Date, Decimal> nightly = nightlyRates(b, typeId, startDate, endDate);
      String nightStatus = b.Status__c == 'Cancelled'
        ? 'Cancelled'
        : (b.Status__c == 'No Show'
            ? 'No Show'
            : ((b.Status__c == 'Active' ||
                b.Status__c == 'Completed')
                ? 'In House'
                : 'Reserved'));
      for (
        Integer i = 0; i < PMS_DateUtil.nightsBetween(startDate, endDate); i++
      ) {
        Date d = startDate.addDays(i);
        if (postedDates.contains(d)) {
          continue;
        }
        toInsert.add(
          new PMS_Room_Night__c(
            Reservation__c = b.Id,
            Stay_Date__c = d,
            Room__c = b.Space__c,
            Room_Type__c = typeId,
            Rate__c = nightly.containsKey(d)
              ? nightly.get(d)
              : b.Rate_Amount__c,
            Status__c = nightStatus
          )
        );
      }
    }
    if (!toDelete.isEmpty()) {
      delete toDelete;
    }
    if (!toInsert.isEmpty()) {
      insert toInsert;
    }
  }

  private static Map<Date, Decimal> nightlyRates(
    PMS_Booking__c b,
    Id typeId,
    Date startDate,
    Date endDate
  ) {
    Map<Date, Decimal> result = new Map<Date, Decimal>();
    if (b.Rate_Plan__c == null) {
      return result;
    }
    PMS_PricingService.QuoteRequest qr = new PMS_PricingService.QuoteRequest();
    qr.module = PMS_ModuleConfig.HOTEL;
    qr.ratePlanId = b.Rate_Plan__c;
    qr.spaceTypeId = typeId;
    qr.spaceId = b.Space__c;
    qr.startDate = startDate;
    qr.endDate = endDate;
    for (PMS_PricingService.QuoteLine l : PMS_PricingService.quote(qr).lines) {
      result.put(l.serviceDate, l.amount);
    }
    return result;
  }

  /** Recomputes Inventory Day rows (total, sold, out of order) for the room types and dates given. */
  @NamespaceAccessible
  public static void refreshInventory(
    Set<Id> roomTypeIds,
    Date fromDate,
    Date toDate
  ) {
    roomTypeIds.remove(null);
    if (
      roomTypeIds.isEmpty() ||
      fromDate == null ||
      toDate == null ||
      toDate <= fromDate
    ) {
      return;
    }
    if (fromDate.daysBetween(toDate) > MAX_INVENTORY_DAYS) {
      toDate = fromDate.addDays(MAX_INVENTORY_DAYS);
    }
    Map<Id, Integer> totalByType = new Map<Id, Integer>();
    Map<Id, Integer> oooByType = new Map<Id, Integer>();
    for (PMS_Space__c s : [
      SELECT Space_Type__c, Operational_Status__c
      FROM PMS_Space__c
      WHERE Space_Type__c IN :roomTypeIds AND Bookable__c = TRUE
    ]) {
      totalByType.put(
        s.Space_Type__c,
        (totalByType.containsKey(s.Space_Type__c)
          ? totalByType.get(s.Space_Type__c)
          : 0) + 1
      );
      if (
        PMS_AvailabilityService.UNSELLABLE_SPACE_STATUSES.contains(
          s.Operational_Status__c
        )
      ) {
        oooByType.put(
          s.Space_Type__c,
          (oooByType.containsKey(s.Space_Type__c)
            ? oooByType.get(s.Space_Type__c)
            : 0) + 1
        );
      }
    }
    Map<String, Integer> sold = new Map<String, Integer>();
    for (AggregateResult ar : [
      SELECT Room_Type__c rt, Stay_Date__c d, COUNT(Id) n
      FROM PMS_Room_Night__c
      WHERE
        Room_Type__c IN :roomTypeIds
        AND Stay_Date__c >= :fromDate
        AND Stay_Date__c < :toDate
        AND Status__c NOT IN :INACTIVE_NIGHT_STATUSES
      GROUP BY Room_Type__c, Stay_Date__c
    ]) {
      sold.put(
        key((Id) ar.get('rt'), (Date) ar.get('d')),
        (Integer) ar.get('n')
      );
    }
    Map<String, PMS_Inventory_Day__c> existing = new Map<String, PMS_Inventory_Day__c>();
    for (PMS_Inventory_Day__c inv : [
      SELECT Id, Room_Type__c, Inventory_Date__c, Stop_Sell__c
      FROM PMS_Inventory_Day__c
      WHERE
        Room_Type__c IN :roomTypeIds
        AND Inventory_Date__c >= :fromDate
        AND Inventory_Date__c < :toDate
    ]) {
      existing.put(key(inv.Room_Type__c, inv.Inventory_Date__c), inv);
    }
    List<PMS_Inventory_Day__c> toUpsert = new List<PMS_Inventory_Day__c>();
    for (Id typeId : roomTypeIds) {
      for (Date d = fromDate; d < toDate; d = d.addDays(1)) {
        String k = key(typeId, d);
        PMS_Inventory_Day__c inv = existing.containsKey(k)
          ? existing.get(k)
          : new PMS_Inventory_Day__c(
              Room_Type__c = typeId,
              Inventory_Date__c = d
            );
        inv.Total_Rooms__c = totalByType.containsKey(typeId)
          ? totalByType.get(typeId)
          : 0;
        inv.Out_Of_Order__c = oooByType.containsKey(typeId)
          ? oooByType.get(typeId)
          : 0;
        inv.Sold__c = sold.containsKey(k) ? sold.get(k) : 0;
        toUpsert.add(inv);
      }
    }
    upsert toUpsert;
  }

  private static String key(Id typeId, Date d) {
    return String.valueOf(typeId) + '|' + String.valueOf(d);
  }
}
