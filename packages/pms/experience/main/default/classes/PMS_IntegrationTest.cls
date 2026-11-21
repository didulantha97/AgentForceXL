@isTest
private class PMS_IntegrationTest {
  private static final String SECRET = 'test-secret';

  private static void call(String body, String signature) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/pms/payments';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body);
    if (signature != null) {
      req.addHeader('X-PMS-Signature', signature);
    }
    RestContext.request = req;
    RestContext.response = new RestResponse();
    PMS_PaymentWebhook.receive();
  }

  private static String sign(String body) {
    return EncodingUtil.convertToHex(
      Crypto.generateMac('hmacSHA256', Blob.valueOf(body), Blob.valueOf(SECRET))
    );
  }

  @isTest
  static void webhookUpsertsPaymentOnce() {
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Webhook_Secret__c = SECRET
    );
    PMS_ExperienceTestFactory.Hotel h = PMS_ExperienceTestFactory.hotel(1);
    PMS_Booking__c b = PMS_BookingService.createBooking(
      PMS_ExperienceTestFactory.hotelRequest(h, Date.today().addDays(10), 1)
    );
    String bookingNumber = [SELECT Name FROM PMS_Booking__c WHERE Id = :b.Id]
    .Name;
    String body = JSON.serialize(
      new Map<String, Object>{
        'reference' => 'pi_123',
        'amount' => 500,
        'status' => 'succeeded',
        'type' => 'Deposit',
        'method' => 'Card',
        'bookingNumber' => bookingNumber
      }
    );

    call(body, sign(body));
    Assert.areEqual(200, RestContext.response.statusCode);
    call(body, sign(body)); // gateway retry
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Payment__c WHERE Gateway_Reference__c = 'pi_123']
    );
    PMS_ExperienceTestFactory.num(
      500,
      [SELECT Amount_Paid__c FROM PMS_Booking__c WHERE Id = :b.Id]
      .Amount_Paid__c,
      'deposit applied'
    );

    call(body, 'bad-signature');
    Assert.areEqual(401, RestContext.response.statusCode);
    call(body, null);
    Assert.areEqual(401, RestContext.response.statusCode);

    String unknown = JSON.serialize(
      new Map<String, Object>{
        'reference' => 'pi_9',
        'amount' => 1,
        'bookingNumber' => 'BKG-NOPE'
      }
    );
    call(unknown, sign(unknown));
    Assert.areEqual(400, RestContext.response.statusCode);
  }

  @isTest
  static void webhookRecordsConfirmedPaymentWhenLicenceSuspended() {
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Webhook_Secret__c = SECRET
    );
    PMS_ExperienceTestFactory.Hotel h = PMS_ExperienceTestFactory.hotel(1);
    PMS_Booking__c b = PMS_BookingService.createBooking(
      PMS_ExperienceTestFactory.hotelRequest(h, Date.today().addDays(10), 1)
    );
    String bookingNumber = [SELECT Name FROM PMS_Booking__c WHERE Id = :b.Id]
    .Name;
    String body = JSON.serialize(
      new Map<String, Object>{
        'reference' => 'pi_susp',
        'amount' => 500,
        'status' => 'succeeded',
        'type' => 'Deposit',
        'method' => 'Card',
        'bookingNumber' => bookingNumber
      }
    );
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    call(body, 'bad-signature');
    Assert.areEqual(401, RestContext.response.statusCode);
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PMS_Payment__c
        WHERE Gateway_Reference__c = 'pi_susp'
      ]
    );
    call(body, sign(body));
    Assert.areEqual(
      200,
      RestContext.response.statusCode,
      RestContext.response.responseBody.toString()
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Payment__c
        WHERE Gateway_Reference__c = 'pi_susp'
      ]
    );
    Database.SaveResult blocked = Database.insert(
      new PMS_Payment__c(
        Gateway_Reference__c = 'manual-3',
        Amount__c = 1,
        Booking__c = b.Id
      ),
      false
    );
    Assert.isFalse(blocked.isSuccess(), 'exemption does not leak');
  }

  @isTest
  static void statusMapping() {
    Assert.areEqual('Succeeded', PMS_PaymentWebhook.mapStatus('captured'));
    Assert.areEqual('Failed', PMS_PaymentWebhook.mapStatus('refused'));
    Assert.areEqual('Refunded', PMS_PaymentWebhook.mapStatus('refunded'));
    Assert.areEqual('Pending', PMS_PaymentWebhook.mapStatus(null));
    Assert.isFalse(
      PMS_PaymentWebhook.signatureValid('x', 'y'),
      'No secret configured'
    );
  }

  @isTest
  static void agentActions() {
    PMS_ExperienceTestFactory.Hotel h = PMS_ExperienceTestFactory.hotel(1);
    Date monday = PMS_ExperienceTestFactory.futureMonday();

    PMS_AgentActions.AvailabilityRequest ar = new PMS_AgentActions.AvailabilityRequest();
    ar.siteId = h.site.Id;
    ar.startDate = monday;
    ar.endDate = monday.addDays(2);
    ar.guests = 2;
    PMS_AgentActions.AvailabilityResult avail = PMS_CheckAvailabilityAction.run(
      new List<PMS_AgentActions.AvailabilityRequest>{ ar }
    )[0];
    Assert.isTrue(avail.available);
    Assert.areEqual(1, avail.availableCount);
    Assert.isTrue(avail.summary.contains('Double'));

    PMS_GetQuoteAction.Request qr = new PMS_GetQuoteAction.Request();
    qr.module = 'Hotel';
    qr.ratePlanId = h.plan.Id;
    qr.spaceTypeId = h.doubleRoom.Id;
    qr.startDate = monday;
    qr.endDate = monday.addDays(2);
    PMS_GetQuoteAction.Result quote = PMS_GetQuoteAction.run(
      new List<PMS_GetQuoteAction.Request>{ qr }
    )[0];
    PMS_ExperienceTestFactory.num(2688, quote.gross, 'quote total');

    PMS_CreateBookingAction.Request cr = new PMS_CreateBookingAction.Request();
    cr.module = 'Hotel';
    cr.siteId = h.site.Id;
    cr.spaceTypeId = h.doubleRoom.Id;
    cr.ratePlanId = h.plan.Id;
    cr.accountId = h.guestAccount.Id;
    cr.contactId = h.guest.Id;
    cr.startDate = monday;
    cr.endDate = monday.addDays(2);
    cr.adults = 2;
    PMS_CreateBookingAction.Result ok = PMS_CreateBookingAction.run(
      new List<PMS_CreateBookingAction.Request>{ cr }
    )[0];
    Assert.isTrue(ok.success, ok.message);
    Assert.areEqual(
      'AI Agent',
      [SELECT Channel__c FROM PMS_Booking__c WHERE Id = :ok.bookingId]
      .Channel__c
    );

    PMS_CreateBookingAction.Result full = PMS_CreateBookingAction.run(
      new List<PMS_CreateBookingAction.Request>{ cr }
    )[0];
    Assert.isFalse(full.success, 'Second booking finds no room');

    avail = PMS_CheckAvailabilityAction.run(
      new List<PMS_AgentActions.AvailabilityRequest>{ ar }
    )[0];
    Assert.isFalse(avail.available);
  }
}
