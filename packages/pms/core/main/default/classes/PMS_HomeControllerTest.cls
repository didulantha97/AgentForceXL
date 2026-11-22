@isTest
private class PMS_HomeControllerTest {
  /**
   * A query that is wrong (bad field, bad syntax) shows up as a warning on the page. Permission
   * warnings are allowed in tests (the running user's access varies by org), syntax errors are not.
   */
  private static void assertNoQueryErrors(PMS_HomeController.HomeData d) {
    for (String w : d.warnings) {
      String u = w.toUpperCase();
      Assert.isFalse(
        u.contains('MALFORMED') ||
          u.contains('NO SUCH COLUMN') ||
          u.contains('UNEXPECTED TOKEN') ||
          u.contains('DIDN\'T UNDERSTAND RELATIONSHIP') ||
          u.contains('INVALID FIELD') ||
          u.contains('BIND VARIABLE') ||
          u.contains('DOES NOT EXIST IN THE BINDMAP') ||
          u.contains('NULL POINTER') ||
          u.contains('INVALID CONVERSION'),
        'Query or code error in ' + d.module + ' home: ' + w
      );
    }
  }

  private static void assertShape(
    PMS_HomeController.HomeData d,
    String module
  ) {
    Assert.areEqual(module, d.module);
    Assert.isNotNull(d.currencyCode, 'display currency');
    Assert.isNotNull(d.generatedAt);
    assertNoQueryErrors(d);
    if (d.warnings.isEmpty()) {
      Assert.areEqual(6, d.kpis.size(), module + ' shows six KPI tiles');
      Assert.isTrue(
        d.charts.size() >= 3,
        module + ' shows at least three charts'
      );
      Assert.isFalse(d.sections.isEmpty(), module + ' shows work queues');
    }
  }

  @testSetup
  static void data() {
    // Hotel: one guest in house, one arriving today, one leaving today, one dirty room.
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(4);
    PMS_Booking__c stay = PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, Date.today(), 2)
    );
    PMS_BookingService.checkIn(stay.Id, null);
    PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, Date.today(), 1)
    );
    PMS_Booking__c leaving = PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, Date.today().addDays(-1), 1)
    );
    PMS_BookingService.checkIn(leaving.Id, null);
    update new PMS_Space__c(
      Id = h.rooms[3].Id,
      Operational_Status__c = 'Dirty'
    );
    insert new Case(
      Subject = 'Extra towels',
      PMS_Site__c = h.site.Id,
      PMS_Module__c = 'Hotel',
      Priority = 'High'
    );

    // Property: an active lease ending within 90 days, an urgent work order, a vendor bill.
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
    r.module = 'Property';
    r.siteId = p.site.Id;
    r.spaceId = p.unit.Id;
    r.accountId = p.tenant.Id;
    r.startDate = Date.today().addMonths(-11);
    r.endDate = Date.today().addDays(30);
    r.status = 'Active';
    PMS_BookingService.createBooking(r);
    PMS_Work_Order__c wo = new PMS_Work_Order__c(
      Site__c = p.site.Id,
      Space__c = p.unit.Id,
      Subject__c = 'Leaking tap',
      Priority__c = 'Urgent',
      Status__c = 'New',
      Scheduled_Date__c = Date.today().addDays(2)
    );
    insert wo;
    insert new PMS_Vendor_Bill__c(
      Site__c = p.site.Id,
      Work_Order__c = wo.Id,
      Amount__c = 1200,
      Status__c = 'Submitted',
      Due_Date__c = Date.today().addDays(10)
    );
    insert new Case(
      Subject = 'Broken window',
      PMS_Site__c = p.site.Id,
      PMS_Module__c = 'Property'
    );

    // Projects: a red project with a blocked late task, a critical RAID item, submitted time, an approval.
    PMS_Project__c proj = PMS_TestDataFactory.projectWithTasks();
    proj.Health__c = 'Red';
    proj.Budget__c = 100000;
    proj.Actual_Cost__c = 60000;
    update proj;
    insert new PMS_Project_Task__c(
      Name = 'Permits',
      Project__c = proj.Id,
      Start_Date__c = Date.today().addDays(-10),
      End_Date__c = Date.today().addDays(-1),
      Status__c = 'Blocked',
      Estimated_Hours__c = 8
    );
    insert new PMS_RAID_Item__c(
      Description__c = 'Supplier delay',
      Project__c = proj.Id,
      RAID_Type__c = 'Risk',
      Severity__c = 'Critical',
      Status__c = 'Open',
      Due_Date__c = Date.today().addDays(5)
    );
    insert new PMS_Time_Entry__c(
      Project__c = proj.Id,
      Entry_Date__c = Date.today(),
      Hours__c = 4,
      Approval_Status__c = 'Submitted'
    );
    insert new PMS_Approval_Request__c(
      Project__c = proj.Id,
      Title__c = 'Change order',
      Status__c = 'Pending',
      Amount__c = 5000,
      Due_Date__c = Date.today().addDays(7)
    );
    insert new PMS_Milestone__c(
      Name = 'Design done',
      Project__c = proj.Id,
      Due_Date__c = Date.today().addDays(-3),
      Status__c = 'Completed',
      Amount__c = 10000
    );

    // Practice: a matter in intake with an unsigned form, and a billed consultation.
    PMS_TestDataFactory.Practice pr = PMS_TestDataFactory.practice();
    PMS_Matter__c m = new PMS_Matter__c(
      Name = 'Matter 1',
      Account__c = pr.client.Id,
      Site__c = pr.site.Id,
      Status__c = 'Intake'
    );
    insert m;
    insert new PMS_Intake_Form__c(Matter__c = m.Id);
    insert new PMS_Charge__c(
      Matter__c = m.Id,
      Charge_Type__c = 'Consultation Fee',
      Quantity__c = 1,
      Unit_Price__c = 800,
      Tax_Rate__c = 25,
      Status__c = 'Pending'
    );
    List<PMS_Invoice__c> invs = PMS_BillingService.invoicePendingCharges(
      Database.query(PMS_BillingService.pendingChargeQuery()),
      Date.today().addDays(-45)
    );
    for (PMS_Invoice__c inv : invs) {
      inv.Due_Date__c = Date.today().addDays(-40);
    }
    update invs;
    if (!invs.isEmpty()) {
      insert new PMS_Payment__c(
        Invoice__c = invs[0].Id,
        Account__c = pr.client.Id,
        Amount__c = 100,
        Status__c = 'Succeeded',
        Payment_Type__c = 'Payment',
        Received_Date__c = Date.today()
      );
    }
  }

  @isTest
  static void hotelHome() {
    Test.startTest();
    PMS_HomeController.HomeData d = PMS_HomeController.getHome('Hotel', null);
    Test.stopTest();
    assertShape(d, 'Hotel');
    Assert.areEqual(1, d.sites.size(), 'only hotel sites are offered');
    if (d.warnings.isEmpty()) {
      Map<String, PMS_HomeController.Kpi> byKey = new Map<String, PMS_HomeController.Kpi>();
      for (PMS_HomeController.Kpi k : d.kpis) {
        byKey.put(k.key, k);
      }
      PMS_TestDataFactory.num(
        2,
        byKey.get('arrivals').value,
        'two arrivals today'
      );
      PMS_TestDataFactory.num(
        2,
        byKey.get('inhouse').value,
        'two guests in house'
      );
      Assert.isFalse(
        d.agenda.isEmpty(),
        'arrivals and departures on the agenda'
      );
    }
  }

  @isTest
  static void hotelHomeForOneSite() {
    Id siteId = [SELECT Id FROM PMS_Site__c WHERE Module__c = 'Hotel' LIMIT 1]
    .Id;
    PMS_HomeController.HomeData d = PMS_HomeController.getHome('Hotel', siteId);
    Assert.areEqual(String.valueOf(siteId), String.valueOf(d.siteId));
    assertShape(d, 'Hotel');
  }

  @isTest
  static void propertyHome() {
    PMS_HomeController.HomeData d = PMS_HomeController.getHome(
      'Property',
      null
    );
    assertShape(d, 'Property');
    if (d.warnings.isEmpty()) {
      Boolean sawWorkOrder = false;
      for (PMS_HomeController.Section s : d.sections) {
        if (s.key == 'workorders') {
          sawWorkOrder = s.total == 1;
        }
      }
      Assert.isTrue(sawWorkOrder, 'the urgent work order is in the queue');
    }
  }

  @isTest
  static void pendingApplicationAppearsInThePropertyApplicationsQueue() {
    PMS_Site__c site = [
      SELECT Id
      FROM PMS_Site__c
      WHERE RecordType.DeveloperName = 'Property'
      LIMIT 1
    ];
    PMS_Space__c unit = [
      SELECT Id
      FROM PMS_Space__c
      WHERE Site__c = :site.Id
      LIMIT 1
    ];
    Account acc = PMS_TestDataFactory.account('Applicant AB');
    Contact applicant = PMS_TestDataFactory.contact(acc.Id, 'Applicant');
    PMS_Application__c pending = new PMS_Application__c(
      Applicant__c = applicant.Id,
      Space__c = unit.Id,
      Decision__c = 'Pending'
    );
    PMS_Application__c decided = new PMS_Application__c(
      Applicant__c = applicant.Id,
      Space__c = unit.Id,
      Decision__c = 'Approved'
    );
    insert new List<PMS_Application__c>{ pending, decided };

    Test.startTest();
    PMS_HomeController.HomeData d = PMS_HomeController.getHome(
      'Property',
      site.Id
    );
    Test.stopTest();
    assertNoQueryErrors(d);
    Assert.isTrue(d.warnings.isEmpty(), 'no warnings: ' + d.warnings);
    PMS_HomeController.Section apps;
    for (PMS_HomeController.Section sec : d.sections) {
      if (sec.key == 'applications') {
        apps = sec;
      }
    }
    Assert.isNotNull(apps, 'the Property home has an applications queue');
    Assert.areEqual(1, apps.total, 'only the pending application is queued');
    Assert.areEqual(pending.Id, apps.items[0].recordId);
  }

  @isTest
  static void projectsHome() {
    PMS_HomeController.HomeData d = PMS_HomeController.getHome(
      'Projects',
      null
    );
    assertShape(d, 'Projects');
    if (d.warnings.isEmpty()) {
      for (PMS_HomeController.Kpi k : d.kpis) {
        if (k.key == 'risk') {
          PMS_TestDataFactory.num(1, k.value, 'one red project');
          Assert.areEqual('error', k.tone);
        }
      }
    }
  }

  @isTest
  static void practiceHome() {
    PMS_HomeController.HomeData d = PMS_HomeController.getHome(
      'Practice',
      null
    );
    assertShape(d, 'Practice');
  }

  @isTest
  static void adminHomeAllSitesAndOneSite() {
    PMS_HomeController.HomeData all = PMS_HomeController.getHome('Admin', null);
    assertShape(all, 'Admin');
    Assert.areEqual(
      3,
      all.sites.size(),
      'admin can pick any site (hotel, property, practice)'
    );

    Id propertySite = [
      SELECT Id
      FROM PMS_Site__c
      WHERE Module__c = 'Property'
      LIMIT 1
    ]
    .Id;
    Test.startTest();
    PMS_HomeController.HomeData one = PMS_HomeController.getHome(
      'Admin',
      propertySite
    );
    Test.stopTest();
    Assert.areEqual('Admin', one.module);
    assertNoQueryErrors(one);
    Boolean propertyTiles = false;
    for (PMS_HomeController.Kpi k : one.kpis) {
      propertyTiles = propertyTiles || k.key == 'vacant';
    }
    if (one.warnings.isEmpty()) {
      Assert.isTrue(
        propertyTiles,
        'admin with a property site uses property tiles'
      );
    }
  }

  @isTest
  static void badInputIsRejected() {
    try {
      PMS_HomeController.getHome('Casino', null);
      Assert.fail('unknown module should throw');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('Casino'));
    }
    // A malformed site id falls back to all sites rather than failing.
    PMS_HomeController.HomeData d = PMS_HomeController.getHome(
      'Practice',
      'not-an-id'
    );
    Assert.isNull(d.siteId);
  }

  @isTest
  static void partsCoverEveryModule() {
    for (
      String m : new List<String>{ 'Hotel', 'Property', 'Projects', 'Practice' }
    ) {
      Assert.isFalse(PMS_HomeController.partsFor(m, false).isEmpty(), m);
    }
    Assert.isTrue(
      PMS_HomeController.partsFor('Admin', true).contains('dashboard')
    );
  }
}
