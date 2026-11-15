@isTest
private class PMS_BookingServiceTest {
  @isTest
  static void hotelReservationCreatesRoomNightsAndInventory() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(2);
    Date monday = PMS_TestDataFactory.futureMonday();
    Test.startTest();
    PMS_Booking__c b = PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, monday, 2)
    );
    Test.stopTest();

    b = [
      SELECT
        Space__c,
        Status__c,
        Total_Amount__c,
        Rate_Amount__c,
        Room_Night_Revenue__c,
        Nights__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.isNotNull(b.Space__c, 'A room of the requested type is assigned');
    Assert.areEqual('Confirmed', b.Status__c);
    PMS_TestDataFactory.num(2, b.Nights__c, 'nights');
    PMS_TestDataFactory.num(
      2400,
      b.Room_Night_Revenue__c,
      'Two weekday nights at 1200'
    );
    PMS_TestDataFactory.num(2688, b.Total_Amount__c, 'total');

    List<PMS_Room_Night__c> nights = [
      SELECT Stay_Date__c, Status__c
      FROM PMS_Room_Night__c
      WHERE Reservation__c = :b.Id
      ORDER BY Stay_Date__c
    ];
    Assert.areEqual(2, nights.size());
    Assert.areEqual(monday, nights[0].Stay_Date__c);
    Assert.areEqual('Reserved', nights[0].Status__c);

    PMS_Inventory_Day__c inv = [
      SELECT Total_Rooms__c, Sold__c, Available__c
      FROM PMS_Inventory_Day__c
      WHERE Room_Type__c = :h.doubleRoom.Id AND Inventory_Date__c = :monday
    ];
    PMS_TestDataFactory.num(2, inv.Total_Rooms__c, 'total rooms');
    PMS_TestDataFactory.num(1, inv.Sold__c, 'sold');
    PMS_TestDataFactory.num(1, inv.Available__c, 'available');
  }

  @isTest
  static void doubleBookingIsBlocked() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    Date d = Date.today().addDays(30);
    PMS_BookingService.createBooking(PMS_TestDataFactory.hotelRequest(h, d, 3));
    try {
      PMS_BookingService.createBooking(
        PMS_TestDataFactory.hotelRequest(h, d.addDays(1), 1)
      );
      Assert.fail('Expected no availability');
    } catch (PMS_Exception e) {
      Assert.isTrue(e.getMessage().contains('free'));
    }
    PMS_BookingService.BookingRequest direct = PMS_TestDataFactory.hotelRequest(
      h,
      d.addDays(1),
      1
    );
    direct.spaceId = h.rooms[0].Id;
    try {
      PMS_BookingService.createBooking(direct);
      Assert.fail('Expected the space to be booked');
    } catch (PMS_Exception e) {
      Assert.isTrue(e.getMessage().contains('already booked'));
    }
    Datetime s = PMS_DateUtil.toDatetime(
      d.addDays(1),
      Time.newInstance(15, 0, 0, 0),
      'Europe/Stockholm'
    );
    Database.SaveResult sr = Database.insert(
      new PMS_Booking__c(
        RecordTypeId = PMS_ModuleConfig.bookingRecordTypeId('Hotel'),
        Space__c = h.rooms[0].Id,
        Start__c = s,
        End__c = s.addDays(1),
        Status__c = 'Confirmed'
      ),
      false
    );
    Assert.isFalse(sr.isSuccess(), 'Trigger blocks overlapping inserts too');
  }

  @isTest
  static void frontDeskLifecycle() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(2);
    PMS_Booking__c b = PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, Date.today().addDays(5), 2)
    );
    Id otherRoom = [SELECT Space__c FROM PMS_Booking__c WHERE Id = :b.Id]
      .Space__c == h.rooms[0].Id
      ? h.rooms[1].Id
      : h.rooms[0].Id;

    Test.startTest();
    PMS_BookingService.move(b.Id, otherRoom, Date.today().addDays(6));
    PMS_BookingService.checkIn(b.Id, null);
    insert new PMS_Charge__c(
      Booking__c = b.Id,
      Charge_Type__c = 'Extra',
      Quantity__c = 1,
      Unit_Price__c = 100,
      Tax_Rate__c = 12,
      Status__c = 'Pending'
    );
    PMS_BookingService.checkOut(b.Id);
    Test.stopTest();

    b = [
      SELECT Status__c, Space__c, Total_Amount__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.areEqual('Completed', b.Status__c);
    Assert.areEqual(otherRoom, b.Space__c);
    PMS_TestDataFactory.num(
      112,
      b.Total_Amount__c,
      'Total now follows real charges'
    );
    Assert.areEqual(
      'Dirty',
      [SELECT Operational_Status__c FROM PMS_Space__c WHERE Id = :otherRoom]
      .Operational_Status__c
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Case
        WHERE PMS_Booking__c = :b.Id AND PMS_Module__c = 'Hotel'
      ]
    );
    PMS_Invoice__c folio = [
      SELECT RecordType.DeveloperName, Subtotal__c, Tax_Total__c, Status__c
      FROM PMS_Invoice__c
      WHERE Booking__c = :b.Id
    ];
    Assert.areEqual('Folio', folio.RecordType.DeveloperName);
    PMS_TestDataFactory.num(100, folio.Subtotal__c, 'subtotal');
    PMS_TestDataFactory.num(12, folio.Tax_Total__c, 'tax');
  }

  @isTest
  static void lifecycleGuards() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_Booking__c b = PMS_BookingService.createBooking(
      PMS_TestDataFactory.hotelRequest(h, Date.today().addDays(5), 1)
    );
    try {
      PMS_BookingService.checkOut(b.Id);
      Assert.fail('Cannot check out before check-in');
    } catch (PMS_Exception e) {
      Assert.isNotNull(e.getMessage());
    }
    PMS_BookingService.cancel(b.Id, 'Changed plans');
    b = [
      SELECT Status__c, Special_Requests__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.areEqual('Cancelled', b.Status__c);
    Assert.isTrue(b.Special_Requests__c.contains('Changed plans'));
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Room_Night__c
        WHERE Reservation__c = :b.Id AND Status__c = 'Cancelled'
      ]
    );
    try {
      PMS_BookingService.checkIn(b.Id, null);
      Assert.fail('Cannot check in a cancelled booking');
    } catch (PMS_Exception e) {
      Assert.isNotNull(e.getMessage());
    }
    try {
      PMS_BookingService.move(b.Id, null, Date.today());
      Assert.fail('Cannot move a cancelled booking');
    } catch (PMS_Exception e) {
      Assert.isNotNull(e.getMessage());
    }
    try {
      PMS_BookingService.createBooking(new PMS_BookingService.BookingRequest());
      Assert.fail('Module required');
    } catch (PMS_Exception e) {
      Assert.isNotNull(e.getMessage());
    }
    delete b;
  }

  @isTest
  static void leaseCreatesRentSchedule() {
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
    r.module = 'Property';
    r.siteId = p.site.Id;
    r.spaceId = p.unit.Id;
    r.accountId = p.tenant.Id;
    r.startDate = Date.newInstance(2027, 1, 1);
    r.endDate = Date.newInstance(2028, 1, 1);
    PMS_Booking__c lease = PMS_BookingService.createBooking(r);
    lease = [
      SELECT RecordType.DeveloperName, Rate_Amount__c, Rent_Frequency__c
      FROM PMS_Booking__c
      WHERE Id = :lease.Id
    ];
    Assert.areEqual('Lease', lease.RecordType.DeveloperName);
    PMS_TestDataFactory.num(9000, lease.Rate_Amount__c, 'rent');
    Assert.areEqual('Monthly', lease.Rent_Frequency__c);
    PMS_Lease_Charge_Schedule__c s = [
      SELECT Amount__c, Next_Run_Date__c, End_Date__c
      FROM PMS_Lease_Charge_Schedule__c
      WHERE Lease__c = :lease.Id
    ];
    PMS_TestDataFactory.num(9000, s.Amount__c, 'schedule amount');
    Assert.areEqual(Date.newInstance(2027, 1, 1), s.Next_Run_Date__c);
    Assert.areEqual(Date.newInstance(2027, 12, 31), s.End_Date__c);
  }

  @isTest
  static void appointmentUsesServiceDuration() {
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
    b = [
      SELECT Start__c, End__c, Total_Amount__c, RecordType.DeveloperName
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.areEqual('Appointment', b.RecordType.DeveloperName);
    PMS_TestDataFactory.num(
      30,
      (b.End__c.getTime() - b.Start__c.getTime()) / 60000,
      'minutes'
    );
    PMS_TestDataFactory.num(
      1000,
      b.Total_Amount__c,
      '800 per session + 25% module VAT (service has no tax rate)'
    );
  }
}
