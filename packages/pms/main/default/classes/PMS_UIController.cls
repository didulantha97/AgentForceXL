/**
 * Apex controller for the PMS Lightning Web Components.
 * Reads run in user mode (record sharing + field-level security are enforced);
 * writes go through the service classes, which apply the business rules.
 */
public with sharing class PMS_UIController {
  // ================================================================ shared pickers

  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String detail;
    Option(String label, String value, String detail) {
      this.label = label;
      this.value = value;
      this.detail = detail;
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<String> getEnabledModules() {
    return PMS_ModuleConfig.enabledModules();
  }

  @AuraEnabled(cacheable=true)
  public static List<Option> getSites(String module) {
    List<Option> result = new List<Option>();
    String soql = 'SELECT Id, Name, City__c FROM PMS_Site__c WHERE Status__c = \'Active\'';
    if (String.isNotBlank(module)) {
      soql += ' AND Module__c = :module';
    }
    soql += ' ORDER BY Name LIMIT 200';
    for (
      PMS_Site__c s : (List<PMS_Site__c>) Database.queryWithBinds(
        soql,
        new Map<String, Object>{ 'module' => module },
        AccessLevel.USER_MODE
      )
    ) {
      result.add(new Option(s.Name, s.Id, s.City__c));
    }
    return result;
  }

  @AuraEnabled(cacheable=true)
  public static List<Option> getSpaceTypes(Id siteId) {
    List<Option> result = new List<Option>();
    for (PMS_Space_Type__c t : [
      SELECT Id, Name, Default_Rate__c
      FROM PMS_Space_Type__c
      WHERE Site__c = :siteId OR Site__c = NULL
      WITH USER_MODE
      ORDER BY Name
    ]) {
      result.add(
        new Option(
          t.Name,
          t.Id,
          t.Default_Rate__c == null ? null : String.valueOf(t.Default_Rate__c)
        )
      );
    }
    return result;
  }

  @AuraEnabled(cacheable=true)
  public static List<Option> getRatePlans(Id siteId, String module) {
    List<Option> result = new List<Option>();
    for (PMS_Rate_Plan__c p : [
      SELECT Id, Name, Pricing_Basis__c
      FROM PMS_Rate_Plan__c
      WHERE
        Active__c = TRUE
        AND Module__c = :module
        AND (Site__c = :siteId
        OR Site__c = NULL)
      WITH USER_MODE
      ORDER BY Name
    ]) {
      result.add(new Option(p.Name, p.Id, p.Pricing_Basis__c));
    }
    return result;
  }

  @AuraEnabled(cacheable=true)
  public static List<Option> getServices() {
    List<Option> result = new List<Option>();
    for (PMS_Service__c s : [
      SELECT Id, Name, Duration_Minutes__c, Price__c
      FROM PMS_Service__c
      WHERE Bookable_Online__c = TRUE
      WITH USER_MODE
      ORDER BY Name
    ]) {
      result.add(
        new Option(
          s.Name,
          s.Id,
          (s.Duration_Minutes__c == null ? '' : s.Duration_Minutes__c + ' min')
        )
      );
    }
    return result;
  }

  // ================================================================ booking wizard

  public class SearchResult {
    @AuraEnabled
    public Id spaceId;
    @AuraEnabled
    public String spaceName;
    @AuraEnabled
    public String spaceType;
    @AuraEnabled
    public Id spaceTypeId;
    @AuraEnabled
    public String floor;
    @AuraEnabled
    public Decimal maxOccupancy;
    @AuraEnabled
    public PMS_PricingService.Quote quote;
  }

  @AuraEnabled
  public static List<SearchResult> searchAvailability(
    String module,
    Id siteId,
    Id spaceTypeId,
    Id ratePlanId,
    Date startDate,
    Date endDate,
    Integer guests
  ) {
    try {
      PMS_Site__c site = [
        SELECT Id, Time_Zone__c, Check_In_Time__c, Check_Out_Time__c
        FROM PMS_Site__c
        WHERE Id = :siteId
        WITH USER_MODE
      ];
      Boolean hotel = module == PMS_ModuleConfig.HOTEL;
      Datetime s = PMS_DateUtil.toDatetime(
        startDate,
        hotel ? site.Check_In_Time__c : Time.newInstance(0, 0, 0, 0),
        site.Time_Zone__c
      );
      Datetime e = PMS_DateUtil.toDatetime(
        endDate,
        hotel ? site.Check_Out_Time__c : Time.newInstance(0, 0, 0, 0),
        site.Time_Zone__c
      );
      List<SearchResult> results = new List<SearchResult>();
      for (
        PMS_Space__c sp : PMS_AvailabilityService.findAvailableSpaces(
          siteId,
          spaceTypeId,
          s,
          e,
          guests
        )
      ) {
        if (results.size() >= 50) {
          break;
        }
        PMS_PricingService.QuoteRequest qr = new PMS_PricingService.QuoteRequest();
        qr.module = module;
        qr.ratePlanId = ratePlanId;
        qr.spaceTypeId = sp.Space_Type__c;
        qr.spaceId = sp.Id;
        qr.startDate = startDate;
        qr.endDate = endDate;
        SearchResult r = new SearchResult();
        r.spaceId = sp.Id;
        r.spaceName = sp.Name;
        r.spaceTypeId = sp.Space_Type__c;
        r.spaceType = sp.Space_Type__r == null ? null : sp.Space_Type__r.Name;
        r.floor = sp.Floor__c;
        r.maxOccupancy = sp.Max_Occupancy__c;
        r.quote = PMS_PricingService.quote(qr);
        results.add(r);
      }
      return results;
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  @AuraEnabled
  public static Id createBooking(String requestJson) {
    try {
      PMS_BookingService.BookingRequest req = (PMS_BookingService.BookingRequest) JSON.deserialize(
        requestJson,
        PMS_BookingService.BookingRequest.class
      );
      return PMS_BookingService.createBooking(req).Id;
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  // ================================================================ room grid (hotel tape chart)

  public class GridRoom {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String roomType;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String floor;
  }

  public class GridBooking {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id spaceId;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String guest;
  }

  public class GridData {
    @AuraEnabled
    public List<GridRoom> rooms = new List<GridRoom>();
    @AuraEnabled
    public List<GridBooking> bookings = new List<GridBooking>();
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Integer days;
    @AuraEnabled
    public String siteName;
  }

  @AuraEnabled
  public static GridData getRoomGrid(Id siteId, Date startDate, Integer days) {
    try {
      Integer span = days == null ? 14 : Math.min(Math.max(days, 1), 62);
      PMS_Site__c site = [
        SELECT Id, Name, Time_Zone__c
        FROM PMS_Site__c
        WHERE Id = :siteId
        WITH USER_MODE
      ];
      GridData g = new GridData();
      g.startDate = startDate;
      g.days = span;
      g.siteName = site.Name;
      for (PMS_Space__c s : [
        SELECT Id, Name, Space_Type__r.Name, Operational_Status__c, Floor__c
        FROM PMS_Space__c
        WHERE Site__c = :siteId AND Bookable__c = TRUE
        WITH USER_MODE
        ORDER BY Floor__c, Name
        LIMIT 300
      ]) {
        GridRoom r = new GridRoom();
        r.id = s.Id;
        r.name = s.Name;
        r.roomType = s.Space_Type__r == null ? null : s.Space_Type__r.Name;
        r.status = s.Operational_Status__c;
        r.floor = s.Floor__c;
        g.rooms.add(r);
      }
      Datetime winStart = PMS_DateUtil.toDatetime(
        startDate,
        Time.newInstance(0, 0, 0, 0),
        site.Time_Zone__c
      );
      Datetime winEnd = PMS_DateUtil.toDatetime(
        startDate.addDays(span),
        Time.newInstance(0, 0, 0, 0),
        site.Time_Zone__c
      );
      for (PMS_Booking__c b : [
        SELECT
          Id,
          Name,
          Space__c,
          Start__c,
          End__c,
          Status__c,
          Account__r.Name,
          Primary_Contact__r.Name
        FROM PMS_Booking__c
        WHERE
          Site__c = :siteId
          AND Space__c != NULL
          AND Start__c < :winEnd
          AND End__c > :winStart
          AND Status__c NOT IN ('Cancelled', 'No Show', 'Inquiry')
        WITH USER_MODE
        LIMIT 2000
      ]) {
        GridBooking gb = new GridBooking();
        gb.id = b.Id;
        gb.name = b.Name;
        gb.spaceId = b.Space__c;
        gb.startDate = PMS_DateUtil.toLocalDate(b.Start__c, site.Time_Zone__c);
        gb.endDate = PMS_DateUtil.toLocalDate(b.End__c, site.Time_Zone__c);
        gb.status = b.Status__c;
        gb.guest = b.Primary_Contact__r != null
          ? b.Primary_Contact__r.Name
          : (b.Account__r == null ? '' : b.Account__r.Name);
        g.bookings.add(gb);
      }
      return g;
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  @AuraEnabled
  public static void moveBooking(
    Id bookingId,
    Id newSpaceId,
    Date newStartDate
  ) {
    try {
      PMS_BookingService.move(bookingId, newSpaceId, newStartDate);
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  // ================================================================ front desk today

  public class DeskRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String guest;
    @AuraEnabled
    public Id roomId;
    @AuraEnabled
    public String room;
    @AuraEnabled
    public String roomType;
    @AuraEnabled
    public Id roomTypeId;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public Integer adults;
  }

  public class DeskData {
    @AuraEnabled
    public List<DeskRow> arrivals = new List<DeskRow>();
    @AuraEnabled
    public List<DeskRow> departures = new List<DeskRow>();
    @AuraEnabled
    public List<DeskRow> inHouse = new List<DeskRow>();
    @AuraEnabled
    public List<GridRoom> freeRooms = new List<GridRoom>();
    @AuraEnabled
    public Integer totalRooms = 0;
    @AuraEnabled
    public Integer dirtyRooms = 0;
  }

  @AuraEnabled
  public static DeskData getFrontDesk(Id siteId, Date businessDate) {
    try {
      PMS_Site__c site = [
        SELECT Id, Time_Zone__c, Check_In_Time__c, Check_Out_Time__c
        FROM PMS_Site__c
        WHERE Id = :siteId
        WITH USER_MODE
      ];
      Date d = businessDate == null
        ? PMS_DateUtil.toLocalDate(Datetime.now(), site.Time_Zone__c)
        : businessDate;
      Datetime dayStart = PMS_DateUtil.toDatetime(
        d,
        Time.newInstance(0, 0, 0, 0),
        site.Time_Zone__c
      );
      Datetime dayEnd = dayStart.addDays(1);
      DeskData data = new DeskData();
      for (PMS_Booking__c b : [
        SELECT
          Id,
          Name,
          Status__c,
          Start__c,
          End__c,
          Space__c,
          Space__r.Name,
          Room_Type_Requested__c,
          Room_Type_Requested__r.Name,
          Balance_Due__c,
          Adults__c,
          Account__r.Name,
          Primary_Contact__r.Name
        FROM PMS_Booking__c
        WHERE
          Site__c = :siteId
          AND RecordType.DeveloperName = 'Reservation'
          AND ((Status__c IN ('Confirmed', 'Tentative')
          AND Start__c >= :dayStart
          AND Start__c < :dayEnd)
          OR Status__c = 'Active')
        WITH USER_MODE
        ORDER BY Start__c
        LIMIT 1000
      ]) {
        DeskRow r = new DeskRow();
        r.id = b.Id;
        r.name = b.Name;
        r.guest = b.Primary_Contact__r != null
          ? b.Primary_Contact__r.Name
          : (b.Account__r == null ? '' : b.Account__r.Name);
        r.roomId = b.Space__c;
        r.room = b.Space__r == null ? null : b.Space__r.Name;
        r.roomTypeId = b.Room_Type_Requested__c;
        r.roomType = b.Room_Type_Requested__r == null
          ? null
          : b.Room_Type_Requested__r.Name;
        r.startDate = PMS_DateUtil.toLocalDate(b.Start__c, site.Time_Zone__c);
        r.endDate = PMS_DateUtil.toLocalDate(b.End__c, site.Time_Zone__c);
        r.status = b.Status__c;
        r.balance = b.Balance_Due__c;
        r.adults = b.Adults__c == null ? null : b.Adults__c.intValue();
        if (b.Status__c == 'Active') {
          if (r.endDate <= d) {
            data.departures.add(r);
          } else {
            data.inHouse.add(r);
          }
        } else {
          data.arrivals.add(r);
        }
      }
      Datetime stayStart = PMS_DateUtil.toDatetime(
        d,
        site.Check_In_Time__c,
        site.Time_Zone__c
      );
      Datetime stayEnd = PMS_DateUtil.toDatetime(
        d.addDays(1),
        site.Check_Out_Time__c,
        site.Time_Zone__c
      );
      for (
        PMS_Space__c s : PMS_AvailabilityService.findAvailableSpaces(
          siteId,
          null,
          stayStart,
          stayEnd,
          0
        )
      ) {
        GridRoom r = new GridRoom();
        r.id = s.Id;
        r.name = s.Name;
        r.roomType = s.Space_Type__r == null ? null : s.Space_Type__r.Name;
        r.status = s.Operational_Status__c;
        r.floor = s.Floor__c;
        data.freeRooms.add(r);
      }
      for (AggregateResult ar : [
        SELECT Operational_Status__c st, COUNT(Id) n
        FROM PMS_Space__c
        WHERE Site__c = :siteId AND Bookable__c = TRUE
        WITH USER_MODE
        GROUP BY Operational_Status__c
      ]) {
        Integer n = (Integer) ar.get('n');
        data.totalRooms += n;
        if ((String) ar.get('st') == 'Dirty') {
          data.dirtyRooms += n;
        }
      }
      return data;
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  @AuraEnabled
  public static void checkIn(Id bookingId, Id roomId) {
    try {
      PMS_BookingService.checkIn(bookingId, roomId);
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  @AuraEnabled
  public static void checkOut(Id bookingId) {
    try {
      PMS_BookingService.checkOut(bookingId);
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  // ================================================================ rent roll (property)

  public class RentRow {
    @AuraEnabled
    public Id unitId;
    @AuraEnabled
    public String unit;
    @AuraEnabled
    public String unitType;
    @AuraEnabled
    public Decimal sizeSqm;
    @AuraEnabled
    public Id leaseId;
    @AuraEnabled
    public String leaseNumber;
    @AuraEnabled
    public String tenant;
    @AuraEnabled
    public Decimal rent;
    @AuraEnabled
    public String frequency;
    @AuraEnabled
    public Date leaseEnd;
    @AuraEnabled
    public Decimal arrears;
    @AuraEnabled
    public Decimal maxDaysOverdue;
    @AuraEnabled
    public String status;
  }

  public class RentRoll {
    @AuraEnabled
    public List<RentRow> rows = new List<RentRow>();
    @AuraEnabled
    public Integer units = 0;
    @AuraEnabled
    public Integer occupied = 0;
    @AuraEnabled
    public Decimal occupancyPct = 0;
    @AuraEnabled
    public Decimal monthlyRent = 0;
    @AuraEnabled
    public Decimal totalArrears = 0;
  }

  @AuraEnabled
  public static RentRoll getRentRoll(Id siteId) {
    try {
      RentRoll rr = new RentRoll();
      Map<Id, RentRow> byUnit = new Map<Id, RentRow>();
      for (PMS_Space__c s : [
        SELECT Id, Name, Space_Type__r.Name, Size_Sqm__c
        FROM PMS_Space__c
        WHERE Site__c = :siteId
        WITH USER_MODE
        ORDER BY Name
        LIMIT 1000
      ]) {
        RentRow r = new RentRow();
        r.unitId = s.Id;
        r.unit = s.Name;
        r.unitType = s.Space_Type__r == null ? null : s.Space_Type__r.Name;
        r.sizeSqm = s.Size_Sqm__c;
        r.status = 'Vacant';
        r.arrears = 0;
        r.maxDaysOverdue = 0;
        byUnit.put(s.Id, r);
      }
      Map<Id, RentRow> byLease = new Map<Id, RentRow>();
      for (PMS_Booking__c l : [
        SELECT
          Id,
          Name,
          Space__c,
          Account__r.Name,
          Rate_Amount__c,
          Rent_Frequency__c,
          End__c,
          Status__c
        FROM PMS_Booking__c
        WHERE
          Space__c IN :byUnit.keySet()
          AND RecordType.DeveloperName = 'Lease'
          AND Status__c IN ('Confirmed', 'Active')
        WITH USER_MODE
        ORDER BY Start__c DESC
      ]) {
        RentRow r = byUnit.get(l.Space__c);
        if (r.leaseId != null) {
          continue; // keep the most recent lease per unit
        }
        r.leaseId = l.Id;
        r.leaseNumber = l.Name;
        r.tenant = l.Account__r == null ? null : l.Account__r.Name;
        r.rent = l.Rate_Amount__c;
        r.frequency = l.Rent_Frequency__c;
        r.leaseEnd = l.End__c == null ? null : l.End__c.date();
        r.status = l.Status__c == 'Active' ? 'Let' : 'Starting';
        byLease.put(l.Id, r);
      }
      if (!byLease.isEmpty()) {
        for (PMS_Invoice__c inv : [
          SELECT Booking__c, Balance__c, Days_Overdue__c
          FROM PMS_Invoice__c
          WHERE
            Booking__c IN :byLease.keySet()
            AND Status__c IN ('Issued', 'Partially Paid', 'Overdue')
          WITH USER_MODE
        ]) {
          RentRow r = byLease.get(inv.Booking__c);
          if (inv.Days_Overdue__c != null && inv.Days_Overdue__c > 0) {
            r.arrears += inv.Balance__c == null ? 0 : inv.Balance__c;
            r.maxDaysOverdue = Math.max(r.maxDaysOverdue, inv.Days_Overdue__c);
          }
        }
      }
      for (RentRow r : byUnit.values()) {
        rr.rows.add(r);
        rr.units++;
        if (r.leaseId != null) {
          rr.occupied++;
          rr.monthlyRent += monthly(r.rent, r.frequency);
        }
        rr.totalArrears += r.arrears;
      }
      rr.occupancyPct = rr.units == 0
        ? 0
        : (Decimal.valueOf(rr.occupied) * 100 / rr.units).setScale(1);
      return rr;
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  private static Decimal monthly(Decimal rent, String frequency) {
    if (rent == null) {
      return 0;
    }
    switch on frequency {
      when 'Weekly' {
        return (rent * 52 / 12).setScale(2);
      }
      when 'Quarterly' {
        return (rent / 3).setScale(2);
      }
      when 'Annually' {
        return (rent / 12).setScale(2);
      }
      when else {
        return rent;
      }
    }
  }

  // ================================================================ gantt (project)

  public class GanttTask {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id parentId;
    @AuraEnabled
    public Id predecessorId;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public Decimal percentComplete;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String assignee;
    @AuraEnabled
    public Boolean isMilestone = false;
  }

  public class GanttData {
    @AuraEnabled
    public String projectName;
    @AuraEnabled
    public Date projectStart;
    @AuraEnabled
    public Date projectEnd;
    @AuraEnabled
    public List<GanttTask> tasks = new List<GanttTask>();
  }

  @AuraEnabled
  public static GanttData getGantt(Id projectId) {
    try {
      PMS_Project__c p = [
        SELECT Id, Name, Start_Date__c, End_Date__c
        FROM PMS_Project__c
        WHERE Id = :projectId
        WITH USER_MODE
      ];
      GanttData g = new GanttData();
      g.projectName = p.Name;
      g.projectStart = p.Start_Date__c;
      g.projectEnd = p.End_Date__c;
      for (PMS_Project_Task__c t : [
        SELECT
          Id,
          Name,
          Parent_Task__c,
          Predecessor__c,
          Start_Date__c,
          End_Date__c,
          Percent_Complete__c,
          Status__c,
          Assignee__r.Name
        FROM PMS_Project_Task__c
        WHERE Project__c = :projectId
        WITH USER_MODE
        ORDER BY Start_Date__c NULLS LAST, Name
        LIMIT 1000
      ]) {
        GanttTask gt = new GanttTask();
        gt.id = t.Id;
        gt.name = t.Name;
        gt.parentId = t.Parent_Task__c;
        gt.predecessorId = t.Predecessor__c;
        gt.startDate = t.Start_Date__c;
        gt.endDate = t.End_Date__c;
        gt.percentComplete = t.Percent_Complete__c;
        gt.status = t.Status__c;
        gt.assignee = t.Assignee__r == null ? null : t.Assignee__r.Name;
        g.tasks.add(gt);
        g.projectStart = minDate(g.projectStart, t.Start_Date__c);
        g.projectEnd = maxDate(g.projectEnd, t.End_Date__c);
      }
      for (PMS_Milestone__c m : [
        SELECT Id, Name, Due_Date__c, Status__c
        FROM PMS_Milestone__c
        WHERE Project__c = :projectId AND Due_Date__c != NULL
        WITH USER_MODE
        ORDER BY Due_Date__c
      ]) {
        GanttTask gt = new GanttTask();
        gt.id = m.Id;
        gt.name = m.Name;
        gt.startDate = m.Due_Date__c;
        gt.endDate = m.Due_Date__c;
        gt.status = m.Status__c;
        gt.isMilestone = true;
        g.tasks.add(gt);
        g.projectStart = minDate(g.projectStart, m.Due_Date__c);
        g.projectEnd = maxDate(g.projectEnd, m.Due_Date__c);
      }
      return g;
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  @AuraEnabled
  public static void updateTaskDates(Id taskId, Date startDate, Date endDate) {
    try {
      if (startDate != null && endDate != null && endDate < startDate) {
        throw new PMS_Exception(
          'The end date must be on or after the start date.'
        );
      }
      PMS_Project_Task__c t = new PMS_Project_Task__c(
        Id = taskId,
        Start_Date__c = startDate,
        End_Date__c = endDate
      );
      update as user t;
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  private static Date minDate(Date a, Date b) {
    return a == null ? b : (b == null || a <= b ? a : b);
  }

  private static Date maxDate(Date a, Date b) {
    return a == null ? b : (b == null || a >= b ? a : b);
  }

  // ================================================================ practitioner calendar (practice)

  public class CalAppointment {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id practitionerId;
    @AuraEnabled
    public Datetime startTime;
    @AuraEnabled
    public Datetime endTime;
    @AuraEnabled
    public String client;
    @AuraEnabled
    public String service;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String mode;
  }

  public class CalData {
    @AuraEnabled
    public List<Option> practitioners = new List<Option>();
    @AuraEnabled
    public List<CalAppointment> appointments = new List<CalAppointment>();
  }

  @AuraEnabled
  public static CalData getPractitionerWeek(Id siteId, Date weekStart) {
    try {
      CalData c = new CalData();
      Set<Id> ids = new Set<Id>();
      for (PMS_Practitioner__c p : [
        SELECT Id, Name, Speciality__c
        FROM PMS_Practitioner__c
        WHERE Active__c = TRUE AND (Site__c = :siteId OR Site__c = NULL)
        WITH USER_MODE
        ORDER BY Name
        LIMIT 50
      ]) {
        c.practitioners.add(new Option(p.Name, p.Id, p.Speciality__c));
        ids.add(p.Id);
      }
      Datetime ws = Datetime.newInstance(
        weekStart,
        Time.newInstance(0, 0, 0, 0)
      );
      Datetime we = ws.addDays(7);
      for (PMS_Booking__c b : [
        SELECT
          Id,
          Name,
          Practitioner__c,
          Start__c,
          End__c,
          Primary_Contact__r.Name,
          Account__r.Name,
          Service__r.Name,
          Status__c,
          Appointment_Mode__c
        FROM PMS_Booking__c
        WHERE
          Practitioner__c IN :ids
          AND Start__c < :we
          AND End__c > :ws
          AND Status__c NOT IN ('Cancelled')
        WITH USER_MODE
        ORDER BY Start__c
        LIMIT 2000
      ]) {
        CalAppointment a = new CalAppointment();
        a.id = b.Id;
        a.name = b.Name;
        a.practitionerId = b.Practitioner__c;
        a.startTime = b.Start__c;
        a.endTime = b.End__c;
        a.client = b.Primary_Contact__r != null
          ? b.Primary_Contact__r.Name
          : (b.Account__r == null ? '' : b.Account__r.Name);
        a.service = b.Service__r == null ? null : b.Service__r.Name;
        a.status = b.Status__c;
        a.mode = b.Appointment_Mode__c;
        c.appointments.add(a);
      }
      return c;
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  /**
   * Free start times for a practitioner on a day, in 15-minute steps inside working hours.
   * Working Hours like "09:00-17:00" are used when present; otherwise 09:00-17:00 on weekdays.
   */
  @AuraEnabled
  public static List<Datetime> getFreeSlots(
    Id practitionerId,
    Id serviceId,
    Date day
  ) {
    try {
      PMS_Practitioner__c p = [
        SELECT Id, Working_Hours__c
        FROM PMS_Practitioner__c
        WHERE Id = :practitionerId
        WITH USER_MODE
      ];
      Integer duration = 60;
      if (serviceId != null) {
        PMS_Service__c svc = [
          SELECT Duration_Minutes__c
          FROM PMS_Service__c
          WHERE Id = :serviceId
          WITH USER_MODE
        ];
        duration = svc.Duration_Minutes__c == null
          ? 60
          : svc.Duration_Minutes__c.intValue();
      }
      Time[] hours = workingHours(p.Working_Hours__c);
      List<Datetime> slots = new List<Datetime>();
      if (
        hours == null ||
        (String.isBlank(p.Working_Hours__c) && PMS_DateUtil.isWeekend(day))
      ) {
        return slots;
      }
      Datetime dayStart = Datetime.newInstance(day, hours[0]);
      Datetime dayEnd = Datetime.newInstance(day, hours[1]);
      List<PMS_Booking__c> busy = [
        SELECT Start__c, End__c
        FROM PMS_Booking__c
        WHERE
          Practitioner__c = :practitionerId
          AND Start__c < :dayEnd
          AND End__c > :dayStart
          AND Status__c NOT IN ('Cancelled', 'No Show')
      ];
      for (
        Datetime s = dayStart;
        s.addMinutes(duration) <= dayEnd;
        s = s.addMinutes(15)
      ) {
        Datetime e = s.addMinutes(duration);
        Boolean clash = s < Datetime.now();
        for (PMS_Booking__c b : busy) {
          if (b.Start__c < e && b.End__c > s) {
            clash = true;
            break;
          }
        }
        if (!clash) {
          slots.add(s);
        }
      }
      return slots;
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  @TestVisible
  private static Time[] workingHours(String text) {
    if (String.isBlank(text)) {
      return new List<Time>{
        Time.newInstance(9, 0, 0, 0),
        Time.newInstance(17, 0, 0, 0)
      };
    }
    Matcher m = Pattern.compile(
        '(\\d{1,2}):(\\d{2})\\s*-\\s*(\\d{1,2}):(\\d{2})'
      )
      .matcher(text);
    if (!m.find()) {
      return new List<Time>{
        Time.newInstance(9, 0, 0, 0),
        Time.newInstance(17, 0, 0, 0)
      };
    }
    return new List<Time>{
      Time.newInstance(
        Integer.valueOf(m.group(1)),
        Integer.valueOf(m.group(2)),
        0,
        0
      ),
      Time.newInstance(
        Integer.valueOf(m.group(3)),
        Integer.valueOf(m.group(4)),
        0,
        0
      )
    };
  }

  @AuraEnabled
  public static Id bookAppointment(
    Id practitionerId,
    Id serviceId,
    Id accountId,
    Id contactId,
    Datetime startTime,
    String mode
  ) {
    try {
      PMS_Practitioner__c p = [
        SELECT Id, Site__c
        FROM PMS_Practitioner__c
        WHERE Id = :practitionerId
        WITH USER_MODE
      ];
      if (p.Site__c == null) {
        throw new PMS_Exception(
          'Give the practitioner an office or clinic first.'
        );
      }
      PMS_BookingService.BookingRequest req = new PMS_BookingService.BookingRequest();
      req.module = PMS_ModuleConfig.PRACTICE;
      req.siteId = p.Site__c;
      req.practitionerId = practitionerId;
      req.serviceId = serviceId;
      req.accountId = accountId;
      req.contactId = contactId;
      req.startDatetime = startTime;
      req.appointmentMode = String.isBlank(mode) ? 'In Person' : mode;
      req.channel = 'Direct';
      return PMS_BookingService.createBooking(req).Id;
    } catch (Exception ex) {
      throw auraError(ex);
    }
  }

  // ================================================================ helpers

  private static AuraHandledException auraError(Exception ex) {
    String msg = ex instanceof PMS_Exception
      ? ex.getMessage()
      : ex.getMessage();
    if (ex instanceof DmlException) {
      msg = ((DmlException) ex).getDmlMessage(0);
    }
    AuraHandledException a = new AuraHandledException(msg);
    a.setMessage(msg);
    return a;
  }
}
