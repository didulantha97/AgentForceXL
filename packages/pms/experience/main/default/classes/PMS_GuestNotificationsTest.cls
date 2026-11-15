@isTest
private class PMS_GuestNotificationsTest {
  /** The real path: a website hold is invoiced, Stripe's payment lands, the booking confirms and the guest is emailed once. */
  @isTest
  static void paidWebsiteStayIsConfirmedAndEmailedOnce() {
    PMS_ExperienceTestFactory.Hotel h = PMS_ExperienceTestFactory.hotel(2);
    PMS_BookingService.BookingRequest r = PMS_ExperienceTestFactory.hotelRequest(
      h,
      PMS_ExperienceTestFactory.futureMonday(),
      2
    );
    r.channel = PMS_WebBookingHold.CHANNEL;
    r.status = 'Tentative';
    PMS_Booking__c b = PMS_BookingService.createBooking(r);
    PMS_Invoice__c inv = PMS_WebBookingHold.invoiceHotelStay(b.Id);
    inv = [SELECT Id, Balance__c FROM PMS_Invoice__c WHERE Id = :inv.Id];
    Assert.areEqual(
      0,
      PMS_GuestNotifications.outbox.size(),
      'Nothing is sent before payment'
    );

    Test.startTest();
    insert new PMS_Payment__c(
      Account__c = h.guestAccount.Id,
      Invoice__c = inv.Id,
      Booking__c = b.Id,
      Amount__c = inv.Balance__c,
      Payment_Type__c = 'Payment',
      Method__c = 'Card',
      Received_Date__c = Date.today(),
      Status__c = 'Succeeded',
      Gateway_Reference__c = 'pi_test_confirmation'
    );
    Test.stopTest();

    PMS_Booking__c after = [
      SELECT Name, Status__c, Confirmation_Sent__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.areEqual('Confirmed', after.Status__c);
    Assert.isTrue(after.Confirmation_Sent__c);
    Assert.areEqual(1, PMS_GuestNotifications.outbox.size());
    Messaging.SingleEmailMessage m = PMS_GuestNotifications.outbox[0];
    Assert.areEqual('guest@example.com', m.getToAddresses()[0]);
    Assert.isTrue(m.getSubject().contains(after.Name), m.getSubject());
    Assert.isTrue(
      m.getPlainTextBody().contains('Test Hotel'),
      m.getPlainTextBody()
    );
    Assert.isTrue(
      m.getPlainTextBody().contains('check-in from 15:00'),
      m.getPlainTextBody()
    );
    Assert.isTrue(
      m.getPlainTextBody().contains('Nights: 2'),
      m.getPlainTextBody()
    );
    Assert.isTrue(m.getHtmlBody().contains(after.Name));

    PMS_WebBookingHold.confirmPaid(new Set<Id>{ b.Id });
    Assert.areEqual(
      1,
      PMS_GuestNotifications.outbox.size(),
      'A confirmed booking is never emailed twice'
    );
  }

  @isTest
  static void appointmentConfirmationNamesTreatmentAndPractitioner() {
    PMS_ExperienceTestFactory.Practice p = PMS_ExperienceTestFactory.practice();
    update new PMS_Site__c(
      Id = p.site.Id,
      Time_Zone__c = 'Europe/Stockholm',
      Currency_Code__c = 'SEK',
      Phone__c = '08-123 456'
    );
    Contact client = PMS_ExperienceTestFactory.contact(p.client.Id, 'Client');
    PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
    r.module = PMS_ModuleConfig.PRACTICE;
    r.siteId = p.site.Id;
    r.serviceId = p.service.Id;
    r.practitionerId = p.practitioner.Id;
    r.startDatetime = PMS_DateUtil.toDatetime(
      PMS_ExperienceTestFactory.futureMonday(),
      Time.newInstance(10, 0, 0, 0),
      'Europe/Stockholm'
    );
    r.accountId = p.client.Id;
    r.contactId = client.Id;
    r.adults = 1;
    r.channel = PMS_WebBookingHold.CHANNEL;
    r.status = 'Tentative';
    PMS_Booking__c b = PMS_BookingService.createBooking(r);

    PMS_GuestNotifications.bookingConfirmed(new Set<Id>{ b.Id });

    Assert.areEqual(1, PMS_GuestNotifications.outbox.size());
    String body = PMS_GuestNotifications.outbox[0].getPlainTextBody();
    Assert.isTrue(body.contains('Consultation'), body);
    Assert.isTrue(body.contains('Dr Test'), body);
    Assert.isTrue(body.contains('10:00'), body);
    Assert.isTrue(body.contains('08-123 456'), body);
    Assert.isTrue(
      PMS_GuestNotifications.outbox[0]
        .getSubject()
        .startsWith('Your appointment at Test Clinic')
    );
  }

  @isTest
  static void guestWithoutEmailIsSkipped() {
    PMS_ExperienceTestFactory.Hotel h = PMS_ExperienceTestFactory.hotel(1);
    update new Contact(Id = h.guest.Id, Email = null);
    PMS_Booking__c b = PMS_BookingService.createBooking(
      PMS_ExperienceTestFactory.hotelRequest(
        h,
        PMS_ExperienceTestFactory.futureMonday(),
        1
      )
    );
    PMS_GuestNotifications.bookingConfirmed(new Set<Id>{ b.Id });
    PMS_GuestNotifications.bookingConfirmed(null);
    Assert.areEqual(0, PMS_GuestNotifications.outbox.size());
  }

  @isTest
  static void viewingRequestIsAcknowledged() {
    PMS_ExperienceTestFactory.Property p = PMS_ExperienceTestFactory.property();
    Case c = new Case(
      Subject = 'Viewing request: A-101, Test Building',
      Description = 'Could I see it on a weekday evening?',
      Origin = 'Web',
      Status = 'New',
      Priority = 'Medium',
      SuppliedName = 'Sara Lind',
      SuppliedEmail = 'sara.lind@example.com',
      PMS_Module__c = 'Property',
      PMS_Site__c = p.site.Id,
      PMS_Space__c = p.unit.Id
    );
    Test.startTest();
    insert c;
    Test.stopTest();

    String caseNumber = [SELECT CaseNumber FROM Case WHERE Id = :c.Id]
    .CaseNumber;
    Assert.areEqual(1, PMS_GuestNotifications.outbox.size());
    Messaging.SingleEmailMessage m = PMS_GuestNotifications.outbox[0];
    Assert.areEqual('sara.lind@example.com', m.getToAddresses()[0]);
    Assert.isTrue(m.getSubject().contains(caseNumber), m.getSubject());
    Assert.isTrue(
      m.getPlainTextBody().startsWith('Hello Sara,'),
      m.getPlainTextBody()
    );
    Assert.isTrue(
      m.getPlainTextBody().contains('A-101, Test Building'),
      m.getPlainTextBody()
    );
    Assert.isTrue(
      m.getPlainTextBody().contains('weekday evening'),
      m.getPlainTextBody()
    );
  }

  @isTest
  static void otherCasesGetNoEmail() {
    PMS_ExperienceTestFactory.Property p = PMS_ExperienceTestFactory.property();
    insert new List<Case>{
      new Case(
        Subject = 'Leaking tap',
        Origin = 'Phone',
        Status = 'New',
        PMS_Module__c = 'Property',
        PMS_Space__c = p.unit.Id
      ),
      new Case(
        Subject = 'Viewing request: A-101',
        Origin = 'Web',
        Status = 'New',
        PMS_Module__c = 'Property',
        PMS_Space__c = p.unit.Id
      ),
      new Case(
        Subject = 'Question',
        Origin = 'Web',
        Status = 'New',
        SuppliedEmail = 'x@example.com'
      )
    };
    Assert.areEqual(0, PMS_GuestNotifications.outbox.size());
  }

  @isTest
  static void moneyFormatting() {
    Assert.areEqual('3 248.00 SEK', PMS_GuestNotifications.money(3248, 'SEK'));
    Assert.areEqual(
      '1 062.50 SEK',
      PMS_GuestNotifications.money(1062.5, 'SEK')
    );
    Assert.areEqual('950.00', PMS_GuestNotifications.money(950, null));
    Assert.areEqual(
      '1 234 567.89 EUR',
      PMS_GuestNotifications.money(1234567.891, 'EUR')
    );
  }
}
