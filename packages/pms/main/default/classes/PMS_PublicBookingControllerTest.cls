@isTest
private class PMS_PublicBookingControllerTest {
  private class StripeMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      Assert.isTrue(
        req.getBody().contains('expires_at='),
        'Public site links must expire early'
      );
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        '{"id":"cs_test_1","url":"https://checkout.stripe.com/c/pay/cs_test_1","expires_at":' +
          (Datetime.now().addMinutes(35).getTime() / 1000) +
          '}'
      );
      return res;
    }
  }

  @TestSetup
  static void setup() {
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Checkout_Return_URL__c = 'https://example.com/pay'
    );
  }

  private static String guestJson(String lastName) {
    return JSON.serialize(
      new Map<String, Object>{
        'firstName' => 'Web',
        'lastName' => lastName,
        'email' => lastName.toLowerCase() + '@example.com',
        'phone' => '+46 70 000 00 00',
        'notes' => 'Late arrival',
        'website' => '',
        'elapsedMs' => 8000
      }
    );
  }

  private static PMS_TestDataFactory.Hotel hotel() {
    return PMS_TestDataFactory.hotel(2);
  }

  @isTest
  static void catalogListsHotelsClinicsAndHomes() {
    PMS_TestDataFactory.Hotel h = hotel();
    PMS_TestDataFactory.Practice p = PMS_TestDataFactory.practice();
    PMS_TestDataFactory.Property pr = PMS_TestDataFactory.property();

    PMS_PublicBookingController.Catalog c = PMS_PublicBookingController.getCatalog();

    Boolean hotelFound = false;
    for (PMS_PublicBookingController.SiteInfo s : c.hotels) {
      hotelFound |= s.id == h.site.Id;
    }
    Assert.isTrue(hotelFound, 'Hotel listed');
    Assert.isFalse(c.clinics.isEmpty(), 'Clinic listed');
    Assert.isFalse(c.services.isEmpty(), 'Online services listed');
    Assert.isFalse(c.practitioners.isEmpty(), 'Practitioners listed');
    Boolean unitFound = false;
    for (PMS_PublicBookingController.ListingInfo l : c.listings) {
      unitFound |= l.id == pr.unit.Id;
    }
    Assert.isTrue(unitFound, 'Vacant unit listed');
  }

  @isTest
  static void searchBookAndPayForAStay() {
    PMS_TestDataFactory.Hotel h = hotel();
    Date arrive = PMS_TestDataFactory.futureMonday();
    String a = String.valueOf(arrive);
    String d = String.valueOf(arrive.addDays(2));

    List<PMS_PublicBookingController.StayOption> opts = PMS_PublicBookingController.searchStays(
      h.site.Id,
      a,
      d,
      2
    );
    Assert.areEqual(1, opts.size());
    Assert.areEqual(2, opts[0].available);
    Assert.isTrue(opts[0].gross > 0, 'Priced');

    PMS_PublicBookingController.BookingResult r = PMS_PublicBookingController.bookStay(
      h.site.Id,
      h.doubleRoom.Id,
      a,
      d,
      2,
      0,
      guestJson('Stayer')
    );
    Assert.areEqual(64, r.accessKey.length());
    PMS_TestDataFactory.num(
      opts[0].gross,
      r.amount,
      'Invoice matches the quote'
    );

    PMS_Booking__c b = [
      SELECT
        Status__c,
        Channel__c,
        Primary_Contact__r.Email,
        Special_Requests__c,
        (SELECT Status__c FROM Room_Nights__r)
      FROM PMS_Booking__c
      WHERE Id = :r.bookingId
    ];
    Assert.areEqual('Tentative', b.Status__c);
    Assert.areEqual('Website', b.Channel__c);
    Assert.areEqual('stayer@example.com', b.Primary_Contact__r.Email);
    Assert.areEqual(2, b.Room_Nights__r.size());
    for (PMS_Room_Night__c rn : b.Room_Nights__r) {
      Assert.areEqual(
        'Posted',
        rn.Status__c,
        'Prepaid nights are never charged again by the night audit'
      );
    }
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM PMS_Charge__c
        WHERE Booking__c = :r.bookingId AND Charge_Type__c = 'Room Night'
      ]
    );

    // One room left of two.
    Assert.areEqual(
      1,
      PMS_PublicBookingController.searchStays(h.site.Id, a, d, 2)[0].available
    );

    Test.setMock(HttpCalloutMock.class, new StripeMock());
    Test.startTest();
    PMS_PublicBookingController.PayLink link = PMS_PublicBookingController.getPayLink(
      r.bookingId,
      r.accessKey
    );
    Test.stopTest();
    Assert.isTrue(link.url.startsWith('https://checkout.stripe.com/'));
    PMS_TestDataFactory.num(r.amount, link.amount, 'Pays the full amount');
  }

  @isTest
  static void payLinkNeedsTheRightKey() {
    PMS_TestDataFactory.Hotel h = hotel();
    Date arrive = PMS_TestDataFactory.futureMonday();
    PMS_PublicBookingController.BookingResult r = PMS_PublicBookingController.bookStay(
      h.site.Id,
      h.doubleRoom.Id,
      String.valueOf(arrive),
      String.valueOf(arrive.addDays(1)),
      1,
      0,
      guestJson('Keyed')
    );
    Boolean failed = false;
    try {
      PMS_PublicBookingController.getPayLink(
        r.bookingId,
        r.accessKey.toUpperCase().equals(r.accessKey)
          ? r.accessKey.toLowerCase()
          : r.accessKey.toUpperCase()
      );
    } catch (AuraHandledException e) {
      failed = true;
    }
    Assert.isTrue(failed, 'Wrong-case key rejected');
    failed = false;
    try {
      PMS_PublicBookingController.getPayLink(r.bookingId, 'x');
    } catch (AuraHandledException e) {
      failed = true;
    }
    Assert.isTrue(failed, 'Short key rejected');
  }

  @isTest
  static void paidInvoiceConfirmsBooking() {
    PMS_TestDataFactory.Hotel h = hotel();
    Date arrive = PMS_TestDataFactory.futureMonday();
    PMS_PublicBookingController.BookingResult r = PMS_PublicBookingController.bookStay(
      h.site.Id,
      h.doubleRoom.Id,
      String.valueOf(arrive),
      String.valueOf(arrive.addDays(1)),
      1,
      0,
      guestJson('Payer')
    );
    PMS_Invoice__c inv = [
      SELECT Id
      FROM PMS_Invoice__c
      WHERE Booking__c = :r.bookingId
    ];
    Test.startTest();
    update new PMS_Invoice__c(Id = inv.Id, Status__c = 'Paid');
    Test.stopTest();
    Assert.areEqual(
      'Confirmed',
      [SELECT Status__c FROM PMS_Booking__c WHERE Id = :r.bookingId].Status__c
    );
  }

  @isTest
  static void unpaidHoldsAreReleased() {
    PMS_TestDataFactory.Hotel h = hotel();
    Date arrive = PMS_TestDataFactory.futureMonday();
    String a = String.valueOf(arrive);
    String d = String.valueOf(arrive.addDays(2));
    PMS_PublicBookingController.BookingResult r = PMS_PublicBookingController.bookStay(
      h.site.Id,
      h.doubleRoom.Id,
      a,
      d,
      2,
      0,
      guestJson('Dropper')
    );
    Test.setCreatedDate(
      r.bookingId,
      Datetime.now().addMinutes(-(PMS_WebBookingHold.HOLD_MINUTES + 5))
    );

    Test.startTest();
    new PMS_WebBookingCleanup().execute(null);
    Test.stopTest();

    Assert.areEqual(
      'Cancelled',
      [SELECT Status__c FROM PMS_Booking__c WHERE Id = :r.bookingId].Status__c
    );
    Assert.areEqual(
      'Void',
      [SELECT Status__c FROM PMS_Invoice__c WHERE Booking__c = :r.bookingId]
      .Status__c
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PMS_Charge__c
        WHERE Booking__c = :r.bookingId AND Status__c != 'Void'
      ]
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PMS_Room_Night__c
        WHERE Reservation__c = :r.bookingId AND Status__c = 'Posted'
      ]
    );
    Assert.areEqual(
      2,
      PMS_PublicBookingController.searchStays(h.site.Id, a, d, 2)[0].available,
      'Rooms back on sale'
    );
  }

  @isTest
  static void appointmentSlotsAndBooking() {
    PMS_TestDataFactory.Practice p = PMS_TestDataFactory.practice();
    Date day = PMS_TestDataFactory.futureMonday();

    List<PMS_PublicBookingController.Slot> slots = PMS_PublicBookingController.getAppointmentSlots(
      p.service.Id,
      null,
      String.valueOf(day)
    );
    Assert.isFalse(slots.isEmpty(), 'Monday 08:00-16:00 has slots');

    PMS_PublicBookingController.BookingResult r = PMS_PublicBookingController.bookAppointment(
      p.service.Id,
      slots[0].practitionerId,
      JSON.serialize(slots[0].startAt).remove('"'),
      guestJson('Patient')
    );
    Assert.isTrue(r.amount > 0, 'Priced');
    PMS_Booking__c b = [
      SELECT Status__c, Practitioner__c, Start__c
      FROM PMS_Booking__c
      WHERE Id = :r.bookingId
    ];
    Assert.areEqual('Tentative', b.Status__c);
    Assert.areEqual(slots[0].startAt, b.Start__c);

    List<PMS_PublicBookingController.Slot> after = PMS_PublicBookingController.getAppointmentSlots(
      p.service.Id,
      slots[0].practitionerId,
      String.valueOf(day)
    );
    for (PMS_PublicBookingController.Slot s : after) {
      Assert.areNotEqual(
        slots[0].startAt,
        s.startAt,
        'Booked slot no longer offered'
      );
    }
    Boolean failed = false;
    try {
      PMS_PublicBookingController.bookAppointment(
        p.service.Id,
        slots[0].practitionerId,
        JSON.serialize(slots[0].startAt).remove('"'),
        guestJson('Second')
      );
    } catch (AuraHandledException e) {
      failed = true;
    }
    Assert.isTrue(failed, 'Same slot cannot be booked twice');
  }

  @isTest
  static void enquiryCreatesCase() {
    PMS_TestDataFactory.Property pr = PMS_TestDataFactory.property();
    String caseNumber = PMS_PublicBookingController.submitEnquiry(
      pr.unit.Id,
      guestJson('Renter')
    );
    Case c = [
      SELECT SuppliedEmail, PMS_Space__c, Origin
      FROM Case
      WHERE CaseNumber = :caseNumber
    ];
    Assert.areEqual('renter@example.com', c.SuppliedEmail);
    Assert.areEqual(pr.unit.Id, c.PMS_Space__c);
  }

  @isTest
  static void spamAndBadInputAreRejected() {
    PMS_TestDataFactory.Hotel h = hotel();
    Date arrive = PMS_TestDataFactory.futureMonday();
    String a = String.valueOf(arrive);
    String d = String.valueOf(arrive.addDays(1));

    Map<String, Object> bot = (Map<String, Object>) JSON.deserializeUntyped(
      guestJson('Bot')
    );
    bot.put('website', 'http://spam.example');
    Map<String, Object> fast = (Map<String, Object>) JSON.deserializeUntyped(
      guestJson('Fast')
    );
    fast.put('elapsedMs', 200);
    Map<String, Object> badEmail = (Map<String, Object>) JSON.deserializeUntyped(
      guestJson('Mail')
    );
    badEmail.put('email', 'not-an-email');

    for (
      String payload : new List<String>{
        JSON.serialize(bot),
        JSON.serialize(fast),
        JSON.serialize(badEmail),
        'garbage'
      }
    ) {
      Boolean failed = false;
      try {
        PMS_PublicBookingController.bookStay(
          h.site.Id,
          h.doubleRoom.Id,
          a,
          d,
          1,
          0,
          payload
        );
      } catch (AuraHandledException e) {
        failed = true;
      }
      Assert.isTrue(failed, 'Rejected: ' + payload);
    }
    // Past dates, too long, too many guests.
    List<List<Object>> badSearches = new List<List<Object>>{
      new List<Object>{
        String.valueOf(Date.today().addDays(-1)),
        String.valueOf(Date.today().addDays(1)),
        1
      },
      new List<Object>{
        a,
        String.valueOf(
          arrive.addDays(PMS_PublicBookingController.MAX_NIGHTS + 1)
        ),
        1
      },
      new List<Object>{ a, d, PMS_PublicBookingController.MAX_GUESTS + 1 },
      new List<Object>{ d, a, 1 }
    };
    for (List<Object> s : badSearches) {
      Boolean failed = false;
      try {
        PMS_PublicBookingController.searchStays(
          h.site.Id,
          (String) s[0],
          (String) s[1],
          (Integer) s[2]
        );
      } catch (AuraHandledException e) {
        failed = true;
      }
      Assert.isTrue(failed, 'Rejected search ' + s);
    }
  }

  @isTest
  static void rateLimitPerEmail() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(
      PMS_PublicBookingController.MAX_PER_EMAIL_PER_HOUR + 1
    );
    Date arrive = PMS_TestDataFactory.futureMonday();
    String a = String.valueOf(arrive);
    String d = String.valueOf(arrive.addDays(1));
    for (
      Integer i = 0; i < PMS_PublicBookingController.MAX_PER_EMAIL_PER_HOUR; i++
    ) {
      PMS_PublicBookingController.bookStay(
        h.site.Id,
        h.doubleRoom.Id,
        a,
        d,
        1,
        0,
        guestJson('Repeat')
      );
    }
    Boolean failed = false;
    try {
      PMS_PublicBookingController.bookStay(
        h.site.Id,
        h.doubleRoom.Id,
        a,
        d,
        1,
        0,
        guestJson('Repeat')
      );
    } catch (AuraHandledException e) {
      failed = true;
    }
    Assert.isTrue(failed, 'Fourth booking within the hour is refused');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Contact WHERE Email = 'repeat@example.com'],
      'Guest contact reused'
    );
  }

  @isTest
  static void workingHoursParsing() {
    Date monday = PMS_TestDataFactory.futureMonday();
    Date saturday = monday.addDays(5);
    Assert.areEqual(
      Time.newInstance(8, 0, 0, 0),
      PMS_PublicBookingController.workingHours('Mon-Fri 08:00-16:00', monday)[0]
    );
    Assert.isNull(
      PMS_PublicBookingController.workingHours('Mon-Fri 08:00-16:00', saturday)
    );
    Assert.areEqual(
      Time.newInstance(17, 0, 0, 0),
      PMS_PublicBookingController.workingHours(
        'Tue-Sat 09:00-17:00',
        saturday
      )[1]
    );
    Assert.isNull(
      PMS_PublicBookingController.workingHours('Tue-Sat 09:00-17:00', monday)
    );
    Assert.areEqual(
      Time.newInstance(10, 0, 0, 0),
      PMS_PublicBookingController.workingHours(
        'Mon-Fri 08:00-16:00; Sat 10:00-14:00',
        saturday
      )[0]
    );
    Assert.isNull(
      PMS_PublicBookingController.workingHours('08:00-16:00', saturday),
      'Plain hours mean weekdays'
    );
    Assert.isNotNull(
      PMS_PublicBookingController.workingHours(null, monday),
      'Blank defaults to office hours'
    );
    Assert.isNull(PMS_PublicBookingController.workingHours('whenever', monday));
  }

  @isTest
  static void cleanupSchedules() {
    Test.startTest();
    List<Id> ids = PMS_WebBookingCleanup.scheduleEvery15Minutes();
    Test.stopTest();
    Assert.areEqual(4, ids.size());
  }
}
