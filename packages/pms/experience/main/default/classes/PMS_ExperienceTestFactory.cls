@isTest
public class PMS_ExperienceTestFactory {
  /**
   * Grants the running user the packaged PMS permission sets so USER_MODE queries see every PMS field,
   * independent of the org's profiles (package build orgs and fresh client orgs have no PMS FLS on profiles).
   */
  public static void grantPmsAccess(List<String> permissionSetNames) {
    Id me = UserInfo.getUserId();
    Set<Id> have = new Set<Id>();
    for (PermissionSetAssignment psa : [
      SELECT PermissionSetId
      FROM PermissionSetAssignment
      WHERE AssigneeId = :me
    ]) {
      have.add(psa.PermissionSetId);
    }
    List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN :permissionSetNames
    ]) {
      if (!have.contains(ps.Id)) {
        toAdd.add(
          new PermissionSetAssignment(AssigneeId = me, PermissionSetId = ps.Id)
        );
      }
    }
    System.runAs(new User(Id = me)) {
      insert toAdd;
    }
  }

  public static Id rt(Schema.SObjectType t, String devName) {
    return PMS_ModuleConfig.recordTypeId(t, devName);
  }

  public static Account account(String name) {
    Account a = new Account(Name = name);
    insert a;
    return a;
  }

  public static Contact contact(Id accountId, String lastName) {
    Contact c = new Contact(
      AccountId = accountId,
      LastName = lastName,
      Email = lastName.toLowerCase() + '@example.com'
    );
    insert c;
    return c;
  }

  public class Hotel {
    public PMS_Site__c site;
    public PMS_Space_Type__c doubleRoom;
    public List<PMS_Space__c> rooms = new List<PMS_Space__c>();
    public PMS_Rate_Plan__c plan;
    public Account guestAccount;
    public Contact guest;
  }

  public static Hotel hotel(Integer roomCount) {
    Hotel h = new Hotel();
    h.site = new PMS_Site__c(
      Name = 'Test Hotel',
      RecordTypeId = rt(PMS_Site__c.SObjectType, 'Hotel'),
      Module__c = 'Hotel',
      Status__c = 'Active',
      Time_Zone__c = 'Europe/Stockholm',
      Currency_Code__c = 'SEK',
      Check_In_Time__c = Time.newInstance(15, 0, 0, 0),
      Check_Out_Time__c = Time.newInstance(11, 0, 0, 0)
    );
    insert h.site;
    h.doubleRoom = new PMS_Space_Type__c(
      Name = 'Double',
      Site__c = h.site.Id,
      Default_Rate__c = 1000,
      Default_Occupancy__c = 2
    );
    insert h.doubleRoom;
    for (Integer i = 1; i <= roomCount; i++) {
      h.rooms.add(
        new PMS_Space__c(
          Name = String.valueOf(100 + i),
          RecordTypeId = rt(PMS_Space__c.SObjectType, 'Room'),
          Site__c = h.site.Id,
          Space_Type__c = h.doubleRoom.Id,
          Max_Occupancy__c = 2,
          Bookable__c = true,
          Operational_Status__c = 'Available'
        )
      );
    }
    insert h.rooms;
    h.plan = new PMS_Rate_Plan__c(
      Name = 'BAR',
      Site__c = h.site.Id,
      Module__c = 'Hotel',
      Pricing_Basis__c = 'Per Night',
      Tax_Rate__c = 12,
      Active__c = true,
      Currency_Code__c = 'SEK'
    );
    insert h.plan;
    insert new List<PMS_Rate__c>{
      new PMS_Rate__c(
        Rate_Plan__c = h.plan.Id,
        Space_Type__c = h.doubleRoom.Id,
        Amount__c = 1200
      ),
      new PMS_Rate__c(
        Rate_Plan__c = h.plan.Id,
        Space_Type__c = h.doubleRoom.Id,
        Amount__c = 1500,
        Days_Of_Week__c = 'Friday;Saturday'
      )
    };
    h.guestAccount = account('Guest Co');
    h.guest = contact(h.guestAccount.Id, 'Guest');
    return h;
  }

  public static PMS_BookingService.BookingRequest hotelRequest(
    Hotel h,
    Date arrival,
    Integer nights
  ) {
    PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
    r.module = 'Hotel';
    r.siteId = h.site.Id;
    r.spaceTypeId = h.doubleRoom.Id;
    r.ratePlanId = h.plan.Id;
    r.accountId = h.guestAccount.Id;
    r.contactId = h.guest.Id;
    r.startDate = arrival;
    r.endDate = arrival.addDays(nights);
    r.adults = 2;
    return r;
  }

  public class Property {
    public PMS_Site__c site;
    public PMS_Space__c unit;
    public Account tenant;
  }

  public static Property property() {
    Property p = new Property();
    p.site = new PMS_Site__c(
      Name = 'Test Building',
      RecordTypeId = rt(PMS_Site__c.SObjectType, 'Property'),
      Module__c = 'Property',
      Status__c = 'Active',
      Time_Zone__c = 'Europe/Stockholm'
    );
    insert p.site;
    p.unit = new PMS_Space__c(
      Name = 'A-101',
      RecordTypeId = rt(PMS_Space__c.SObjectType, 'Unit'),
      Site__c = p.site.Id,
      Base_Rate__c = 9000,
      Size_Sqm__c = 55,
      Bookable__c = true,
      Operational_Status__c = 'Available'
    );
    insert p.unit;
    p.tenant = account('Tenant AB');
    return p;
  }

  public class Practice {
    public PMS_Site__c site;
    public PMS_Practitioner__c practitioner;
    public PMS_Service__c service;
    public Account client;
  }

  public static Practice practice() {
    Practice p = new Practice();
    p.site = new PMS_Site__c(
      Name = 'Test Clinic',
      RecordTypeId = rt(PMS_Site__c.SObjectType, 'Practice_Branch'),
      Module__c = 'Practice',
      Status__c = 'Active'
    );
    insert p.site;
    p.practitioner = new PMS_Practitioner__c(
      Name = 'Dr Test',
      Site__c = p.site.Id,
      Active__c = true,
      Working_Hours__c = '08:00-16:00'
    );
    insert p.practitioner;
    p.service = new PMS_Service__c(
      Name = 'Consultation',
      Duration_Minutes__c = 30,
      Price__c = 800,
      Bookable_Online__c = true
    );
    insert p.service;
    p.client = account('Client One');
    return p;
  }

  public static PMS_Project__c projectWithTasks() {
    Account a = account('Project Client');
    PMS_Project__c p = new PMS_Project__c(
      Name = 'Office Fit-out',
      Account__c = a.Id,
      Start_Date__c = Date.today(),
      End_Date__c = Date.today().addDays(60),
      Status__c = 'In Progress'
    );
    insert p;
    PMS_Resource__c r = new PMS_Resource__c(
      Name = 'Builder',
      Bill_Rate__c = 600,
      Active__c = true
    );
    insert r;
    PMS_Project_Task__c t1 = new PMS_Project_Task__c(
      Name = 'Design',
      Project__c = p.Id,
      Start_Date__c = Date.today(),
      End_Date__c = Date.today().addDays(10),
      Estimated_Hours__c = 40,
      Assignee__c = r.Id,
      Status__c = 'In Progress',
      Percent_Complete__c = 50
    );
    insert t1;
    insert new PMS_Project_Task__c(
      Name = 'Build',
      Project__c = p.Id,
      Parent_Task__c = t1.Id,
      Predecessor__c = t1.Id,
      Start_Date__c = Date.today().addDays(11),
      End_Date__c = Date.today().addDays(40),
      Estimated_Hours__c = 200
    );
    insert new PMS_Milestone__c(
      Name = 'Handover',
      Project__c = p.Id,
      Due_Date__c = Date.today().addDays(45),
      Amount__c = 50000
    );
    return p;
  }

  /** Numeric assert that treats 2, 2.0 and 2.00 as equal (Integer vs Decimal fields). */
  public static void num(Decimal expected, Decimal actual, String label) {
    Assert.isTrue(
      expected == actual,
      label + ': expected ' + expected + ' but got ' + actual
    );
  }

  /** A Monday at least two weeks ahead, so weekday rate rules are predictable. */
  public static Date futureMonday() {
    Date d = Date.today().addDays(14);
    while (PMS_DateUtil.dayName(d) != 'Monday') {
      d = d.addDays(1);
    }
    return d;
  }
}
