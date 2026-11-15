@isTest
private class PMS_BookingInvoiceActionTest {
  private static PMS_BookingInvoiceAction.Result run(Id bookingId) {
    PMS_BookingInvoiceAction.Request r = new PMS_BookingInvoiceAction.Request();
    r.bookingId = bookingId;
    return PMS_BookingInvoiceAction.run(
      new List<PMS_BookingInvoiceAction.Request>{ r }
    )[0];
  }

  @isTest
  static void hotelStayIsInvoicedOncePerNight() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    Date monday = PMS_TestDataFactory.futureMonday();
    PMS_Booking__c b = PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, monday, 2)
    );

    Test.startTest();
    PMS_BookingInvoiceAction.Result res = run(b.Id);
    PMS_BookingInvoiceAction.Result again = run(b.Id);
    Test.stopTest();

    PMS_TestDataFactory.num(
      2688,
      res.balanceDue,
      'Two weekday nights at 1200 + 12%'
    );
    Assert.areEqual(res.invoiceId, again.invoiceId, 'Open invoice is reused');
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM PMS_Charge__c
        WHERE Booking__c = :b.Id AND Charge_Type__c = 'Room Night'
      ]
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PMS_Charge__c
        WHERE Booking__c = :b.Id AND Charge_Type__c = 'Other'
      ],
      'No lump-sum charge any more'
    );
    // The night audit only picks Reserved / In House nights, so it has nothing left to charge.
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PMS_Room_Night__c
        WHERE Reservation__c = :b.Id AND Status__c IN ('Reserved', 'In House')
      ]
    );
  }

  @isTest
  static void inHouseGuestPaysRemainingNightsAndExtras() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    Date today = PMS_DateUtil.toLocalDate(Datetime.now(), 'Europe/Stockholm');
    PMS_Booking__c b = PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, today, 1)
    );
    PMS_BookingService.checkIn(b.Id, null);
    insert new PMS_Charge__c(
      Booking__c = b.Id,
      Account__c = h.guestAccount.Id,
      Charge_Type__c = 'Extra',
      Quantity__c = 1,
      Unit_Price__c = 100,
      Tax_Rate__c = 12,
      Status__c = 'Pending'
    );
    Decimal nightGross =
      [
        SELECT Rate__c
        FROM PMS_Room_Night__c
        WHERE Reservation__c = :b.Id
        LIMIT 1
      ]
      .Rate__c * 1.12;

    Test.startTest();
    PMS_BookingInvoiceAction.Result res = run(b.Id);
    Test.stopTest();

    PMS_TestDataFactory.num(
      (nightGross + 112).setScale(2),
      res.balanceDue,
      'Night plus extra'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PMS_Charge__c
        WHERE Booking__c = :b.Id AND Status__c = 'Pending'
      ]
    );
  }

  @isTest
  static void appointmentIsInvoicedAtTheServicePrice() {
    PMS_TestDataFactory.Practice p = PMS_TestDataFactory.practice();
    PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
    r.module = 'Practice';
    r.siteId = p.site.Id;
    r.practitionerId = p.practitioner.Id;
    r.serviceId = p.service.Id;
    r.accountId = p.client.Id;
    r.startDatetime = Datetime.newInstance(
      Date.today().addDays(3),
      Time.newInstance(10, 0, 0, 0)
    );
    PMS_Booking__c b = PMS_BookingService.createBooking(r);

    PMS_BookingInvoiceAction.Result res = run(b.Id);
    PMS_TestDataFactory.num(1000, res.balanceDue, '800 + 25%');

    // Once paid, asking again does not bill a second time.
    update new PMS_Invoice__c(Id = res.invoiceId, Status__c = 'Paid');
    Boolean failed = false;
    try {
      run(b.Id);
    } catch (PMS_Exception e) {
      failed = true;
    }
    Assert.isTrue(failed, 'Already invoiced');
  }

  @isTest
  static void leaseUsesItsChargesOrTotal() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
    r.module = 'Property';
    r.siteId = p.site.Id;
    r.spaceId = p.unit.Id;
    r.accountId = p.tenant.Id;
    r.startDate = Date.newInstance(2027, 1, 1);
    r.endDate = Date.newInstance(2027, 2, 1);
    PMS_Booking__c lease = PMS_BookingService.createBooking(r);
    insert new PMS_Charge__c(
      Booking__c = lease.Id,
      Account__c = p.tenant.Id,
      Charge_Type__c = 'Rent',
      Quantity__c = 1,
      Unit_Price__c = 9000,
      Tax_Rate__c = 0,
      Status__c = 'Pending'
    );
    PMS_TestDataFactory.num(
      9000,
      run(lease.Id).balanceDue,
      'Pending rent invoiced'
    );

    PMS_BookingService.BookingRequest r2 = new PMS_BookingService.BookingRequest();
    r2.module = 'Property';
    r2.siteId = p.site.Id;
    r2.spaceId = p.unit.Id;
    r2.accountId = p.tenant.Id;
    r2.startDate = Date.newInstance(2027, 3, 1);
    r2.endDate = Date.newInstance(2027, 4, 1);
    PMS_Booking__c lease2 = PMS_BookingService.createBooking(r2);
    Decimal total = [
      SELECT Total_Amount__c
      FROM PMS_Booking__c
      WHERE Id = :lease2.Id
    ]
    .Total_Amount__c;
    PMS_TestDataFactory.num(
      total,
      run(lease2.Id).balanceDue,
      'Falls back to the booking total'
    );
  }

  @isTest
  static void cancelledBookingIsRefused() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_Booking__c b = PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, Date.today().addDays(9), 1)
    );
    PMS_BookingService.cancel(b.Id, 'Test');
    Boolean failed = false;
    try {
      run(b.Id);
    } catch (PMS_Exception e) {
      failed = true;
    }
    Assert.isTrue(failed, 'Cancelled bookings are not invoiced');
  }
}
