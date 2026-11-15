@isTest
private class PMS_BillingTest {
  private static PMS_Booking__c lease(
    PMS_TestDataFactory.Property p,
    Date startDate
  ) {
    PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
    r.module = 'Property';
    r.siteId = p.site.Id;
    r.spaceId = p.unit.Id;
    r.accountId = p.tenant.Id;
    r.startDate = startDate;
    r.endDate = startDate.addYears(1);
    r.status = 'Active';
    return PMS_BookingService.createBooking(r);
  }

  @isTest
  static void rentRunInvoicingAndPayments() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    Date start = Date.today().addMonths(-2);
    PMS_Booking__c l = lease(p, start);

    Test.startTest();
    Database.executeBatch(
      new PMS_RecurringChargeBatch(Date.today(), false),
      200
    );
    Test.stopTest();

    List<PMS_Charge__c> charges = [
      SELECT Unit_Price__c, Service_Date__c, Status__c
      FROM PMS_Charge__c
      WHERE Booking__c = :l.Id
      ORDER BY Service_Date__c
    ];
    Assert.areEqual(3, charges.size(), 'Three monthly rent charges are due');
    Assert.areEqual(start, charges[0].Service_Date__c);
    Assert.areEqual(
      start.addMonths(3),
      [
        SELECT Next_Run_Date__c
        FROM PMS_Lease_Charge_Schedule__c
        WHERE Lease__c = :l.Id
      ]
      .Next_Run_Date__c
    );

    List<PMS_Invoice__c> invs = PMS_BillingService.invoicePendingCharges(
      Database.query(PMS_BillingService.pendingChargeQuery()),
      Date.today()
    );
    Assert.areEqual(1, invs.size());
    PMS_Invoice__c inv = [
      SELECT
        Id,
        Subtotal__c,
        Tax_Total__c,
        Status__c,
        RecordType.DeveloperName,
        Account__c
      FROM PMS_Invoice__c
      WHERE Id = :invs[0].Id
    ];
    PMS_TestDataFactory.num(27000, inv.Subtotal__c, 'three months rent');
    PMS_TestDataFactory.num(0, inv.Tax_Total__c, 'residential rent has no VAT');
    Assert.areEqual('Rent_Invoice', inv.RecordType.DeveloperName);
    Assert.areEqual('Issued', inv.Status__c);
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PMS_Charge__c
        WHERE Booking__c = :l.Id AND Status__c = 'Pending'
      ]
    );

    insert new PMS_Payment__c(
      Invoice__c = inv.Id,
      Account__c = inv.Account__c,
      Amount__c = 10000,
      Status__c = 'Succeeded',
      Payment_Type__c = 'Payment'
    );
    inv = [
      SELECT Amount_Paid__c, Status__c, Balance__c
      FROM PMS_Invoice__c
      WHERE Id = :inv.Id
    ];
    PMS_TestDataFactory.num(10000, inv.Amount_Paid__c, 'paid');
    Assert.areEqual('Partially Paid', inv.Status__c);

    PMS_Payment__c second = new PMS_Payment__c(
      Invoice__c = inv.Id,
      Account__c = p.tenant.Id,
      Amount__c = 17000,
      Status__c = 'Succeeded'
    );
    insert second;
    inv = [SELECT Status__c, Balance__c FROM PMS_Invoice__c WHERE Id = :inv.Id];
    Assert.areEqual('Paid', inv.Status__c);
    PMS_TestDataFactory.num(0, inv.Balance__c, 'balance');
    PMS_TestDataFactory.num(
      27000,
      [SELECT Amount_Paid__c FROM PMS_Booking__c WHERE Id = :l.Id]
      .Amount_Paid__c,
      'booking paid'
    );

    insert new PMS_Payment__c(
      Invoice__c = inv.Id,
      Account__c = p.tenant.Id,
      Amount__c = 500,
      Status__c = 'Succeeded',
      Payment_Type__c = 'Refund'
    );
    Assert.areEqual(
      'Partially Paid',
      [SELECT Status__c FROM PMS_Invoice__c WHERE Id = :inv.Id].Status__c,
      'A refund reopens the balance'
    );
    delete second;
  }

  @isTest
  static void escalationCompoundsYearly() {
    PMS_Lease_Charge_Schedule__c s = new PMS_Lease_Charge_Schedule__c(
      Amount__c = 1000,
      Escalation_Percent__c = 10,
      Start_Date__c = Date.newInstance(2025, 1, 1)
    );
    s.Lease__r = new PMS_Booking__c();
    PMS_TestDataFactory.num(
      1000,
      PMS_BillingService.escalatedAmount(s, Date.newInstance(2025, 12, 1)),
      'year 1'
    );
    PMS_TestDataFactory.num(
      1100,
      PMS_BillingService.escalatedAmount(s, Date.newInstance(2026, 1, 1)),
      'year 2'
    );
    PMS_TestDataFactory.num(
      1210,
      PMS_BillingService.escalatedAmount(s, Date.newInstance(2027, 3, 1)),
      'year 3'
    );
  }

  @isTest
  static void nightAuditPostsChargesAndMarksNoShows() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(2);
    Date yesterday = Date.today().addDays(-1);
    PMS_Booking__c stay = PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, yesterday, 3)
    );
    PMS_BookingService.checkIn(stay.Id, null);
    PMS_Booking__c noShow = PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, yesterday, 1)
    );

    Test.startTest();
    Database.executeBatch(new PMS_NightAuditBatch(yesterday), 200);
    Test.stopTest();

    PMS_Charge__c c = [
      SELECT Charge_Type__c, Unit_Price__c, Tax_Rate__c, Service_Date__c
      FROM PMS_Charge__c
      WHERE Booking__c = :stay.Id
    ];
    Assert.areEqual('Room Night', c.Charge_Type__c);
    Decimal nightRate = [
      SELECT Rate__c
      FROM PMS_Room_Night__c
      WHERE Reservation__c = :stay.Id AND Stay_Date__c = :yesterday
    ]
    .Rate__c;
    PMS_TestDataFactory.num(
      nightRate,
      c.Unit_Price__c,
      'charge uses the night rate (1200 weekdays, 1500 Fri/Sat)'
    );
    PMS_TestDataFactory.num(12, c.Tax_Rate__c, 'hotel VAT');
    Assert.areEqual(
      'Posted',
      [
        SELECT Status__c
        FROM PMS_Room_Night__c
        WHERE Reservation__c = :stay.Id AND Stay_Date__c = :yesterday
      ]
      .Status__c
    );
    Assert.areEqual(
      'No Show',
      [SELECT Status__c FROM PMS_Booking__c WHERE Id = :noShow.Id].Status__c
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Invoice__c WHERE Booking__c = :stay.Id],
      'In-house guests are not invoiced daily'
    );

    // A later change to the stay keeps the posted night.
    PMS_BookingService.checkOut(stay.Id);
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Room_Night__c
        WHERE Reservation__c = :stay.Id AND Status__c = 'Posted'
      ]
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Invoice__c WHERE Booking__c = :stay.Id],
      'Folio issued at check-out'
    );
  }

  @isTest
  static void dailyJobSchedules() {
    Test.startTest();
    String jobId = System.schedule(
      'PMS Daily Jobs Test',
      '0 0 2 * * ?',
      new PMS_DailyJob()
    );
    Test.stopTest();
    Assert.isNotNull(jobId);
  }

  @isTest
  static void invoiceBatchRuns() {
    PMS_TestDataFactory.Practice pr = PMS_TestDataFactory.practice();
    PMS_Matter__c m = new PMS_Matter__c(
      Name = 'Matter 1',
      Account__c = pr.client.Id,
      Status__c = 'Open',
      Conflict_Check_Status__c = 'Cleared'
    );
    insert m;
    insert new PMS_Charge__c(
      Matter__c = m.Id,
      Charge_Type__c = 'Consultation Fee',
      Quantity__c = 2,
      Unit_Price__c = 800,
      Tax_Rate__c = 25,
      Status__c = 'Pending'
    );
    Test.startTest();
    Database.executeBatch(new PMS_InvoiceBatch(), 100);
    Test.stopTest();
    PMS_Invoice__c inv = [
      SELECT RecordType.DeveloperName, Subtotal__c, Tax_Total__c, Account__c
      FROM PMS_Invoice__c
      WHERE Matter__c = :m.Id
    ];
    Assert.areEqual('Client_Bill', inv.RecordType.DeveloperName);
    Assert.areEqual(pr.client.Id, inv.Account__c);
    PMS_TestDataFactory.num(1600, inv.Subtotal__c, 'fees');
    PMS_TestDataFactory.num(400, inv.Tax_Total__c, 'VAT');
  }
}
