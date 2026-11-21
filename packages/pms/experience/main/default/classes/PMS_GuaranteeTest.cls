@isTest
private class PMS_GuaranteeTest {
  private static final String SECRET = 'whsec_test_secret';

  // ---------------------------------------------------------------- Stripe mock

  private class StripeMock implements HttpCalloutMock {
    Boolean decline = false;
    Boolean failCheckout = false;
    List<HttpRequest> calls = new List<HttpRequest>();
    Integer intents = 0;

    public HttpResponse respond(HttpRequest req) {
      calls.add(req);
      String ep = req.getEndpoint();
      String body = req.getBody() == null
        ? ''
        : EncodingUtil.urlDecode(req.getBody(), 'UTF-8');
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      if (ep.endsWith('/v1/customers')) {
        res.setBody('{"id":"cus_test"}');
      } else if (ep.endsWith('/v1/checkout/sessions')) {
        if (failCheckout) {
          res.setStatusCode(500);
          res.setBody('{"error":{"message":"Checkout unavailable"}}');
        } else {
          res.setBody(
            '{"id":"cs_test","url":"https://checkout.stripe.com/c/pay/cs_test"}'
          );
        }
      } else if (ep.contains('/v1/payment_methods/')) {
        res.setBody(
          '{"id":"pm_test","card":{"brand":"visa","last4":"4242","exp_month":4,"exp_year":2030}}'
        );
      } else if (ep.endsWith('/capture')) {
        String minor = body.substringAfter('amount_to_capture=')
          .substringBefore('&');
        res.setBody(
          '{"id":"pi_hold","status":"succeeded","amount_received":' +
            minor +
            '}'
        );
      } else if (ep.endsWith('/cancel')) {
        res.setBody('{"id":"pi_hold","status":"canceled"}');
      } else if (ep.endsWith('/v1/payment_intents')) {
        intents++;
        if (decline) {
          res.setStatusCode(402);
          res.setBody(
            '{"error":{"code":"authentication_required","message":"Your card requires authentication.","payment_intent":{"id":"pi_declined"}}}'
          );
        } else if (body.contains('capture_method=manual')) {
          res.setBody(
            '{"id":"pi_newhold' +
              intents +
              '","status":"requires_capture","latest_charge":{"payment_method_details":{"card":{"capture_before":1893456000}}}}'
          );
        } else {
          res.setBody('{"id":"pi_charge' + intents + '","status":"succeeded"}');
        }
      } else {
        res.setStatusCode(404);
        res.setBody('{"error":{"message":"unexpected ' + ep + '"}}');
      }
      return res;
    }

    Boolean sent(String fragment) {
      for (HttpRequest r : calls) {
        String b = r.getBody() == null
          ? ''
          : EncodingUtil.urlDecode(r.getBody(), 'UTF-8');
        if (r.getEndpoint().contains(fragment) || b.contains(fragment)) {
          return true;
        }
      }
      return false;
    }
  }

  // ---------------------------------------------------------------- data

  @TestSetup
  static void setup() {
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Webhook_Secret__c = SECRET,
      Checkout_Return_URL__c = 'https://example.com/pay/PMS_PaymentComplete'
    );
    PMS_ExperienceTestFactory.hotel(1);
  }

  private static PMS_Payment_Policy__c policy(String method) {
    PMS_Payment_Policy__c p = new PMS_Payment_Policy__c(
      Name = 'Test ' + method,
      Active__c = true,
      Guarantee_Method__c = method,
      Deposit_Basis__c = 'Fixed Amount',
      Deposit_Value__c = 800,
      Deposit_Due_Days__c = 0,
      Preauth_Hours_Before__c = 24,
      Free_Cancellation_Hours__c = 24,
      Late_Cancel_Basis__c = 'Fixed Amount',
      Late_Cancel_Value__c = 500,
      No_Show_Basis__c = 'Fixed Amount',
      No_Show_Value__c = 600,
      Auto_Charge_Fees__c = true,
      Auto_Send_Card_Link__c = false,
      Release_Hold_On_Checkout__c = true,
      Guest_Terms__c = 'Free cancellation up to 24 hours before arrival.'
    );
    insert p;
    return p;
  }

  private static PMS_Booking__c booking(
    PMS_Payment_Policy__c p,
    Datetime arrival,
    String status
  ) {
    PMS_Site__c site = [SELECT Id FROM PMS_Site__c LIMIT 1];
    PMS_Space__c room = [SELECT Id FROM PMS_Space__c LIMIT 1];
    PMS_Rate_Plan__c plan = [SELECT Id FROM PMS_Rate_Plan__c LIMIT 1];
    Contact guest = [SELECT Id, AccountId FROM Contact LIMIT 1];
    PMS_Booking__c b = new PMS_Booking__c(
      RecordTypeId = PMS_ExperienceTestFactory.rt(
        PMS_Booking__c.SObjectType,
        'Reservation'
      ),
      Site__c = site.Id,
      Space__c = room.Id,
      Rate_Plan__c = plan.Id,
      Account__c = guest.AccountId,
      Primary_Contact__c = guest.Id,
      Start__c = arrival,
      End__c = arrival.addDays(3),
      Adults__c = 2,
      Status__c = status,
      Channel__c = 'Phone',
      Total_Amount__c = 3000,
      Payment_Policy__c = p == null ? null : p.Id
    );
    PMS_GuaranteeTriggerHandler.bypass = true;
    insert b;
    PMS_GuaranteeTriggerHandler.bypass = false;
    return b;
  }

  /** A booking whose guest already saved a card and has a Stripe customer. */
  private static PMS_Booking__c withCard(PMS_Booking__c b) {
    update new Account(Id = b.Account__c, Stripe_Customer_Id__c = 'cus_test');
    PMS_GuaranteeTriggerHandler.bypass = true;
    update new PMS_Booking__c(
      Id = b.Id,
      Stripe_Payment_Method__c = 'pm_test',
      Card_Last4__c = '4242',
      Guarantee_Status__c = 'Card Saved'
    );
    PMS_GuaranteeTriggerHandler.bypass = false;
    return b;
  }

  private static PMS_Booking__c reload(Id bookingId) {
    return PMS_PolicyService.loadOne(bookingId);
  }

  private static PMS_Booking__c inMemory(
    Decimal total,
    Decimal nights,
    Datetime start
  ) {
    Map<String, Object> m = new Map<String, Object>{
      'attributes' => new Map<String, Object>{ 'type' => 'PMS_Booking__c' },
      'Total_Amount__c' => total,
      'Nights__c' => nights,
      'Start__c' => start
    };
    return (PMS_Booking__c) JSON.deserialize(
      JSON.serialize(m),
      PMS_Booking__c.class
    );
  }

  // ---------------------------------------------------------------- policy rules

  @isTest
  static void amountsAndFees() {
    Datetime arrival = Datetime.now().addHours(48);
    PMS_Booking__c b = inMemory(3000, 3, arrival);
    PMS_ExperienceTestFactory.num(
      1000,
      PMS_PolicyService.amountFor('First Night', null, b),
      'first night'
    );
    PMS_ExperienceTestFactory.num(
      900,
      PMS_PolicyService.amountFor('Percent of Total', 30, b),
      'percent'
    );
    PMS_ExperienceTestFactory.num(
      3000,
      PMS_PolicyService.amountFor('Fixed Amount', 5000, b),
      'capped at total'
    );
    PMS_ExperienceTestFactory.num(
      3000,
      PMS_PolicyService.amountFor('Full Stay', null, b),
      'full stay'
    );
    PMS_ExperienceTestFactory.num(
      0,
      PMS_PolicyService.amountFor('None', 10, b),
      'none'
    );

    PMS_Payment_Policy__c p = new PMS_Payment_Policy__c(
      Free_Cancellation_Hours__c = 24,
      Late_Cancel_Basis__c = 'First Night',
      No_Show_Basis__c = 'Percent of Total',
      No_Show_Value__c = 50,
      Fee_Tax_Rate__c = 25,
      Deposit_Due_Days__c = 7,
      Preauth_Hours_Before__c = 72,
      Guarantee_Method__c = 'Deposit'
    );
    PMS_PolicyService.FeeDecision free = PMS_PolicyService.feeFor(
      b,
      p,
      'Cancelled',
      Datetime.now()
    );
    Assert.areEqual('Free cancellation', free.kind);
    PMS_ExperienceTestFactory.num(0, free.gross, 'free');

    PMS_PolicyService.FeeDecision late = PMS_PolicyService.feeFor(
      b,
      p,
      'Cancelled',
      arrival.addHours(-2)
    );
    Assert.areEqual('Late cancellation', late.kind);
    PMS_ExperienceTestFactory.num(1000, late.net, 'late net');
    PMS_ExperienceTestFactory.num(1250, late.gross, 'late gross with 25% VAT');

    PMS_PolicyService.FeeDecision noShow = PMS_PolicyService.feeFor(
      b,
      p,
      'No Show',
      arrival
    );
    PMS_ExperienceTestFactory.num(1500, noShow.net, 'no-show net');

    Assert.isTrue(
      PMS_PolicyService.depositDueNow(b, p, Datetime.now()),
      'arrival in 2 days is inside 7 days'
    );
    Assert.isTrue(
      PMS_PolicyService.holdDueNow(b, p, Datetime.now()),
      'arrival in 48 h is inside 72 h'
    );
    Assert.isFalse(
      PMS_PolicyService.holdDueNow(b, p, Datetime.now().addDays(-5)),
      'five days earlier is too soon'
    );
    Assert.isNull(PMS_PolicyService.feeFor(b, null, 'Cancelled', null).kind);
  }

  @isTest
  static void policyComesFromRatePlanWhenBookingHasNone() {
    PMS_Payment_Policy__c p = policy('Card on File');
    update new PMS_Rate_Plan__c(
      Id = [SELECT Id FROM PMS_Rate_Plan__c LIMIT 1]
      .Id,
      Payment_Policy__c = p.Id
    );
    PMS_Booking__c b = booking(null, Datetime.now().addDays(5), 'Confirmed');
    Assert.areEqual(p.Id, PMS_PolicyService.policyFor(reload(b.Id)).Id);
    p.Active__c = false;
    update p;
    Assert.isNull(
      PMS_PolicyService.policyFor(reload(b.Id)),
      'inactive policies do not apply'
    );
  }

  // ---------------------------------------------------------------- links

  @isTest
  static void cardLinkUsesSetupModeAndEmailsGuest() {
    PMS_Booking__c b = booking(
      policy('Card on File'),
      Datetime.now().addDays(5),
      'Confirmed'
    );
    StripeMock mock = new StripeMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    PMS_GuaranteeService.LinkResult r = PMS_GuaranteeController.sendLink(
      b.Id,
      true
    );
    Test.stopTest();
    Assert.areEqual('https://checkout.stripe.com/c/pay/cs_test', r.url);
    Assert.areEqual('setup', r.mode);
    Assert.isTrue(r.emailed);
    Assert.isTrue(mock.sent('mode=setup'));
    Assert.isTrue(
      mock.sent('setup_intent_data[metadata][pmsSource]=pms-guarantee')
    );
    Assert.areEqual(
      'cus_test',
      [SELECT Stripe_Customer_Id__c FROM Account WHERE Id = :b.Account__c]
      .Stripe_Customer_Id__c
    );
    PMS_Booking__c after = reload(b.Id);
    Assert.areEqual('Awaiting Card', after.Guarantee_Status__c);
    Assert.isNotNull(after.Card_Link_Sent_At__c);
  }

  @isTest
  static void depositLinkTakesPaymentAndSavesCard() {
    PMS_Booking__c b = booking(
      policy('Deposit'),
      Datetime.now().addDays(5),
      'Confirmed'
    );
    StripeMock mock = new StripeMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    PMS_GuaranteeService.LinkResult r = PMS_GuaranteeController.sendLink(
      b.Id,
      false
    );
    Test.stopTest();
    Assert.areEqual('payment', r.mode);
    PMS_ExperienceTestFactory.num(800, r.amount, 'deposit');
    Assert.isTrue(mock.sent('line_items[0][price_data][unit_amount]=80000'));
    Assert.isTrue(
      mock.sent('payment_intent_data[setup_future_usage]=off_session')
    );
    Assert.isTrue(
      mock.sent('payment_intent_data[metadata][paymentType]=Deposit')
    );
    Assert.isFalse(r.emailed);
  }

  @isTest
  static void newBookingGetsLinkAutomatically() {
    PMS_Payment_Policy__c p = policy('Card on File');
    p.Auto_Send_Card_Link__c = true;
    update p;
    Test.setMock(HttpCalloutMock.class, new StripeMock());
    Test.startTest();
    PMS_Site__c site = [SELECT Id FROM PMS_Site__c LIMIT 1];
    Contact guest = [SELECT Id, AccountId FROM Contact LIMIT 1];
    PMS_Booking__c b = new PMS_Booking__c(
      RecordTypeId = PMS_ExperienceTestFactory.rt(
        PMS_Booking__c.SObjectType,
        'Reservation'
      ),
      Site__c = site.Id,
      Space__c = [SELECT Id FROM PMS_Space__c LIMIT 1]
      .Id,
      Account__c = guest.AccountId,
      Primary_Contact__c = guest.Id,
      Start__c = Datetime.now().addDays(10),
      End__c = Datetime.now().addDays(12),
      Adults__c = 1,
      Status__c = 'Confirmed',
      Channel__c = 'Phone',
      Total_Amount__c = 2000,
      Payment_Policy__c = p.Id
    );
    insert b;
    Test.stopTest();
    PMS_Booking__c after = reload(b.Id);
    Assert.isNotNull(
      after.Card_Link_Sent_At__c,
      'Guarantee message: ' + after.Guarantee_Message__c
    );
    Assert.areEqual('Awaiting Card', after.Guarantee_Status__c);
  }

  // ---------------------------------------------------------------- webhook

  private static RestResponse postEvent(String type, Map<String, Object> obj) {
    String body = JSON.serialize(
      new Map<String, Object>{
        'id' => 'evt_' + type,
        'type' => type,
        'created' => Datetime.now().getTime() / 1000,
        'data' => new Map<String, Object>{ 'object' => obj }
      }
    );
    String ts = String.valueOf(Datetime.now().getTime() / 1000);
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/pms/stripe';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body);
    req.headers.put(
      'Stripe-Signature',
      't=' + ts + ',v1=' + PMS_StripeWebhook.sign(ts + '.' + body, SECRET)
    );
    RestContext.request = req;
    RestContext.response = new RestResponse();
    PMS_StripeWebhook.receive();
    return RestContext.response;
  }

  @isTest
  static void savedCardArrivesByWebhookThenDetailsLoad() {
    PMS_Booking__c b = booking(
      policy('Card on File'),
      Datetime.now().addDays(5),
      'Confirmed'
    );
    String name = [SELECT Name FROM PMS_Booking__c WHERE Id = :b.Id].Name;
    RestResponse setupDone = postEvent(
      'checkout.session.completed',
      new Map<String, Object>{
        'id' => 'cs_test',
        'mode' => 'setup',
        'setup_intent' => 'seti_1',
        'amount_total' => 0,
        'metadata' => new Map<String, Object>{ 'bookingNumber' => name }
      }
    );
    Assert.areEqual(
      200,
      setupDone.statusCode,
      'setup-mode sessions are skipped, not rejected'
    );
    RestResponse res = postEvent(
      'setup_intent.succeeded',
      new Map<String, Object>{
        'id' => 'seti_1',
        'payment_method' => 'pm_test',
        'customer' => 'cus_test',
        'metadata' => new Map<String, Object>{
          'bookingNumber' => name,
          'pmsSource' => 'pms-guarantee'
        }
      }
    );
    Assert.areEqual(200, res.statusCode, res.responseBody.toString());
    PMS_Booking__c after = reload(b.Id);
    Assert.areEqual('pm_test', after.Stripe_Payment_Method__c);
    Assert.areEqual('Card Saved', after.Guarantee_Status__c);
    Assert.areEqual('Card on File', after.Guarantee__c);
    Assert.areEqual(0, [SELECT COUNT() FROM PMS_Payment__c]);

    Test.setMock(HttpCalloutMock.class, new StripeMock());
    Test.startTest();
    PMS_GuaranteeController.State s = PMS_GuaranteeController.getState(b.Id);
    Test.stopTest();
    Assert.areEqual('4242', s.cardLast4);
    Assert.areEqual('Visa', s.cardBrand);
    Assert.areEqual('04/2030', s.cardExpiry);
  }

  @isTest
  static void holdEventsAndOwnPaymentsByWebhook() {
    PMS_Booking__c b = withCard(
      booking(
        policy('Pre-authorisation'),
        Datetime.now().addDays(1),
        'Confirmed'
      )
    );
    String name = [SELECT Name FROM PMS_Booking__c WHERE Id = :b.Id].Name;
    Map<String, Object> md = new Map<String, Object>{
      'bookingNumber' => name,
      'pmsSource' => 'pms-guarantee',
      'pmsKind' => 'hold'
    };
    postEvent(
      'payment_intent.amount_capturable_updated',
      new Map<String, Object>{
        'id' => 'pi_h',
        'currency' => 'sek',
        'amount_capturable' => 80000,
        'metadata' => md
      }
    );
    PMS_Booking__c after = reload(b.Id);
    Assert.areEqual('Authorized', after.Preauth_Status__c);
    PMS_ExperienceTestFactory.num(800, after.Preauth_Amount__c, 'hold amount');

    postEvent(
      'payment_intent.canceled',
      new Map<String, Object>{
        'id' => 'pi_h',
        'currency' => 'sek',
        'metadata' => md
      }
    );
    Assert.areEqual('Released', reload(b.Id).Preauth_Status__c);

    Map<String, Object> feeMd = new Map<String, Object>{
      'bookingNumber' => name,
      'pmsSource' => 'pms-guarantee',
      'pmsKind' => 'fee',
      'paymentType' => 'Payment'
    };
    RestResponse res = postEvent(
      'payment_intent.succeeded',
      new Map<String, Object>{
        'id' => 'pi_fee',
        'currency' => 'sek',
        'amount_received' => 50000,
        'metadata' => feeMd
      }
    );
    Assert.areEqual(200, res.statusCode, res.responseBody.toString());
    PMS_Payment__c p = [
      SELECT Amount__c, Booking__c, Status__c
      FROM PMS_Payment__c
      WHERE Gateway_Reference__c = 'pi_fee'
    ];
    PMS_ExperienceTestFactory.num(500, p.Amount__c, 'fee payment');
    Assert.areEqual(b.Id, p.Booking__c);
    postEvent(
      'payment_intent.succeeded',
      new Map<String, Object>{
        'id' => 'pi_fee',
        'currency' => 'sek',
        'amount_received' => 50000,
        'metadata' => feeMd
      }
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Payment__c
        WHERE Gateway_Reference__c = 'pi_fee'
      ],
      'retries do not double-count'
    );

    postEvent(
      'payment_intent.payment_failed',
      new Map<String, Object>{
        'id' => 'pi_x',
        'currency' => 'sek',
        'metadata' => feeMd,
        'last_payment_error' => new Map<String, Object>{
          'message' => 'Card declined'
        }
      }
    );
    Assert.areEqual('Action Needed', reload(b.Id).Guarantee_Status__c);
  }

  @isTest
  static void ordinaryPaymentIntentsAreIgnored() {
    RestResponse res = postEvent(
      'payment_intent.succeeded',
      new Map<String, Object>{
        'id' => 'pi_other',
        'currency' => 'sek',
        'amount_received' => 1000,
        'metadata' => new Map<String, Object>{ 'invoiceNumber' => 'INV-1' }
      }
    );
    Assert.areEqual(200, res.statusCode);
    Assert.isTrue(res.responseBody.toString().contains('ignored'));
  }

  // ---------------------------------------------------------------- policy fees

  @isTest
  static void noShowCapturesFromHold() {
    PMS_Booking__c b = withCard(
      booking(
        policy('Pre-authorisation'),
        Datetime.now().addHours(-2),
        'Confirmed'
      )
    );
    PMS_GuaranteeTriggerHandler.bypass = true;
    update new PMS_Booking__c(
      Id = b.Id,
      Preauth_Intent_Id__c = 'pi_hold',
      Preauth_Status__c = 'Authorized',
      Preauth_Amount__c = 800
    );
    PMS_GuaranteeTriggerHandler.bypass = false;
    StripeMock mock = new StripeMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    update new PMS_Booking__c(Id = b.Id, Status__c = 'No Show');
    Test.stopTest();
    PMS_Booking__c after = reload(b.Id);
    Assert.isTrue(after.Policy_Fee_Charged__c, after.Guarantee_Message__c);
    Assert.isFalse(after.Policy_Pending__c);
    PMS_ExperienceTestFactory.num(
      600,
      after.Policy_Fee_Amount__c,
      'no-show fee'
    );
    Assert.areEqual('Captured', after.Preauth_Status__c);
    Assert.areEqual(
      'Settled',
      after.Guarantee_Status__c,
      after.Guarantee_Message__c
    );
    Assert.isTrue(mock.sent('amount_to_capture=60000'));
    PMS_Charge__c fee = [
      SELECT Invoice__c, Unit_Price__c
      FROM PMS_Charge__c
      WHERE Booking__c = :b.Id AND Charge_Type__c = 'Cancellation Fee'
    ];
    PMS_ExperienceTestFactory.num(600, fee.Unit_Price__c, 'fee charge');
    PMS_Payment__c pay = [
      SELECT Amount__c, Invoice__c
      FROM PMS_Payment__c
      WHERE Gateway_Reference__c = 'pi_hold'
    ];
    Assert.areEqual(fee.Invoice__c, pay.Invoice__c);
    Assert.areEqual(
      'Paid',
      [SELECT Status__c FROM PMS_Invoice__c WHERE Id = :fee.Invoice__c]
      .Status__c
    );
  }

  @isTest
  static void freeCancellationReleasesHoldAndFlagsRefund() {
    PMS_Booking__c b = withCard(
      booking(
        policy('Pre-authorisation'),
        Datetime.now().addDays(5),
        'Confirmed'
      )
    );
    PMS_GuaranteeTriggerHandler.bypass = true;
    update new PMS_Booking__c(
      Id = b.Id,
      Preauth_Intent_Id__c = 'pi_hold',
      Preauth_Status__c = 'Authorized',
      Preauth_Amount__c = 800
    );
    PMS_GuaranteeTriggerHandler.bypass = false;
    insert new PMS_Payment__c(
      Gateway_Reference__c = 'pi_dep',
      Amount__c = 200,
      Account__c = b.Account__c,
      Booking__c = b.Id,
      Payment_Type__c = 'Deposit',
      Method__c = 'Card',
      Received_Date__c = Date.today(),
      Status__c = 'Succeeded'
    );
    StripeMock mock = new StripeMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    update new PMS_Booking__c(Id = b.Id, Status__c = 'Cancelled');
    Test.stopTest();
    PMS_Booking__c after = reload(b.Id);
    Assert.isTrue(after.Policy_Fee_Charged__c);
    Assert.areEqual('Released', after.Preauth_Status__c);
    PMS_ExperienceTestFactory.num(
      200,
      after.Refund_Due__c,
      'deposit to refund'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PMS_Charge__c
        WHERE Booking__c = :b.Id AND Charge_Type__c = 'Cancellation Fee'
      ]
    );
    Assert.isTrue(mock.sent('/cancel'));
  }

  @isTest
  static void lateCancellationUsesDepositThenCard() {
    PMS_Booking__c b = withCard(
      booking(policy('Card on File'), Datetime.now().addHours(5), 'Confirmed')
    );
    insert new PMS_Payment__c(
      Gateway_Reference__c = 'pi_dep',
      Amount__c = 200,
      Account__c = b.Account__c,
      Booking__c = b.Id,
      Payment_Type__c = 'Deposit',
      Method__c = 'Card',
      Received_Date__c = Date.today(),
      Status__c = 'Succeeded'
    );
    StripeMock mock = new StripeMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    update new PMS_Booking__c(Id = b.Id, Status__c = 'Cancelled');
    Test.stopTest();
    PMS_Booking__c after = reload(b.Id);
    Assert.areEqual(
      'Settled',
      after.Guarantee_Status__c,
      after.Guarantee_Message__c
    );
    Assert.isTrue(
      mock.sent('amount=30000'),
      'charges the 300 left after the 200 deposit'
    );
    Assert.isTrue(mock.sent('off_session=true'));
    PMS_Invoice__c inv = [
      SELECT Id, Status__c
      FROM PMS_Invoice__c
      WHERE Booking__c = :b.Id
    ];
    Assert.areEqual('Paid', inv.Status__c);
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM PMS_Payment__c WHERE Invoice__c = :inv.Id],
      'deposit and card charge both pay the fee invoice'
    );
  }

  @isTest
  static void declinedCardNeedsAction() {
    PMS_Booking__c b = withCard(
      booking(policy('Card on File'), Datetime.now().addHours(5), 'Confirmed')
    );
    StripeMock mock = new StripeMock();
    mock.decline = true;
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    update new PMS_Booking__c(Id = b.Id, Status__c = 'Cancelled');
    Test.stopTest();
    PMS_Booking__c after = reload(b.Id);
    Assert.areEqual('Action Needed', after.Guarantee_Status__c);
    Assert.isTrue(
      after.Guarantee_Message__c.contains('authentication'),
      after.Guarantee_Message__c
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Charge__c
        WHERE Booking__c = :b.Id AND Charge_Type__c = 'Cancellation Fee'
      ],
      'the fee is still invoiced'
    );
  }

  @isTest
  static void tentativeCancellationNeedsStaffDecision() {
    PMS_Booking__c b = withCard(
      booking(policy('Card on File'), Datetime.now().addHours(5), 'Tentative')
    );
    Test.setMock(HttpCalloutMock.class, new StripeMock());
    update new PMS_Booking__c(Id = b.Id, Status__c = 'Cancelled');
    PMS_Booking__c after = reload(b.Id);
    Assert.isFalse(
      after.Policy_Pending__c,
      'unconfirmed bookings never get an automatic fee'
    );
    Assert.isTrue(PMS_GuaranteeController.getState(b.Id).canApplyPolicy);
    Test.startTest();
    PMS_GuaranteeController.State s = PMS_GuaranteeController.applyPolicyNow(
      b.Id
    );
    Test.stopTest();
    Assert.isTrue(s.policyApplied);
    PMS_ExperienceTestFactory.num(500, s.policyFee, 'late fee');
    try {
      PMS_GuaranteeController.applyPolicyNow(b.Id);
      Assert.fail('applying twice must fail');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('already'), e.getMessage());
    }
  }

  // ---------------------------------------------------------------- hourly job and console

  @isTest
  static void jobPlacesHoldBeforeArrival() {
    PMS_Booking__c b = withCard(
      booking(
        policy('Pre-authorisation'),
        Datetime.now().addHours(12),
        'Confirmed'
      )
    );
    StripeMock mock = new StripeMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    System.enqueueJob(new PMS_GuaranteeJob.Runner());
    Test.stopTest();
    PMS_Booking__c after = reload(b.Id);
    Assert.areEqual(
      'Authorized',
      after.Preauth_Status__c,
      after.Guarantee_Message__c
    );
    Assert.areEqual('Hold Placed', after.Guarantee_Status__c);
    PMS_ExperienceTestFactory.num(800, after.Preauth_Amount__c, 'hold');
    Assert.isTrue(mock.sent('capture_method=manual'));
    Assert.isNotNull(after.Preauth_Expires_At__c);
  }

  @isTest
  static void jobChargesDepositWhenDue() {
    PMS_Payment_Policy__c p = policy('Deposit');
    p.Deposit_Due_Days__c = 3;
    update p;
    PMS_Booking__c b = withCard(
      booking(p, Datetime.now().addDays(2), 'Confirmed')
    );
    Test.setMock(HttpCalloutMock.class, new StripeMock());
    Test.startTest();
    PMS_GuaranteeJob.run();
    Test.stopTest();
    PMS_Booking__c after = reload(b.Id);
    Assert.areEqual(
      'Deposit Paid',
      after.Guarantee_Status__c,
      after.Guarantee_Message__c
    );
    PMS_Payment__c pay = [
      SELECT Amount__c, Payment_Type__c, Invoice__c
      FROM PMS_Payment__c
      WHERE Booking__c = :b.Id
    ];
    PMS_ExperienceTestFactory.num(800, pay.Amount__c, 'deposit');
    Assert.areEqual('Deposit', pay.Payment_Type__c);
  }

  @isTest
  static void jobSettlesHoldAfterCheckout() {
    PMS_Booking__c b = withCard(
      booking(policy('Pre-authorisation'), Datetime.now().addDays(-3), 'Active')
    );
    PMS_GuaranteeTriggerHandler.bypass = true;
    update new PMS_Booking__c(
      Id = b.Id,
      Preauth_Intent_Id__c = 'pi_hold',
      Preauth_Status__c = 'Authorized',
      Preauth_Amount__c = 800,
      Status__c = 'Completed'
    );
    PMS_GuaranteeTriggerHandler.bypass = false;
    StripeMock mock = new StripeMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    PMS_GuaranteeJob.run();
    Test.stopTest();
    PMS_Booking__c after = reload(b.Id);
    Boolean settled =
      after.Preauth_Status__c == 'Released' ||
      after.Preauth_Status__c == 'Captured';
    Boolean waiting =
      after.Guarantee_Message__c != null &&
      after.Guarantee_Message__c.contains('not invoiced');
    Assert.isTrue(
      settled || waiting,
      'hold settled, or waiting for the folio: ' + after.Guarantee_Message__c
    );
  }

  @isTest
  static void jobHandlesMissingEmailAndEmptyWork() {
    PMS_GuaranteeJob.process(new List<PMS_Booking__c>(), Datetime.now());
    PMS_Payment_Policy__c p = policy('Card on File');
    p.Auto_Send_Card_Link__c = true;
    update p;
    PMS_Booking__c b = booking(p, Datetime.now().addDays(5), 'Confirmed');
    update new Contact(Id = b.Primary_Contact__c, Email = null);
    Test.setMock(HttpCalloutMock.class, new StripeMock());
    Test.startTest();
    PMS_GuaranteeJob.run();
    Test.stopTest();
    Assert.isTrue(
      reload(b.Id).Guarantee_Message__c.contains('no email address')
    );
  }

  @isTest
  static void jobRecordsCardLinkFailures() {
    PMS_Payment_Policy__c p = policy('Card on File');
    p.Auto_Send_Card_Link__c = true;
    update p;
    PMS_Booking__c b = booking(p, Datetime.now().addDays(5), 'Confirmed');
    StripeMock mock = new StripeMock();
    mock.failCheckout = true;
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    PMS_GuaranteeJob.run();
    Test.stopTest();
    Assert.isTrue(
      reload(b.Id).Guarantee_Message__c.contains('Card link failed')
    );
  }

  @isTest
  static void scheduleAndConsoleGuards() {
    String jobId = System.schedule(
      'PMS Guarantees test',
      '0 10 * * * ?',
      new PMS_GuaranteeJob()
    );
    Assert.isNotNull(jobId);
    PMS_Booking__c b = booking(null, Datetime.now().addDays(5), 'Confirmed');
    PMS_GuaranteeController.State s = PMS_GuaranteeController.getState(b.Id);
    Assert.isFalse(s.hasPolicy);
    try {
      PMS_GuaranteeController.placeHold(b.Id);
      Assert.fail('no policy, no hold');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('payment policy'), e.getMessage());
    }
    try {
      PMS_GuaranteeController.captureHold(b.Id, 100);
      Assert.fail('no open hold');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('no open hold'), e.getMessage());
    }
  }

  @isTest
  static void consoleChargesDeposit() {
    PMS_Booking__c b = withCard(
      booking(policy('Deposit'), Datetime.now().addDays(5), 'Confirmed')
    );
    Test.setMock(HttpCalloutMock.class, new StripeMock());
    Test.startTest();
    PMS_GuaranteeController.State s = PMS_GuaranteeController.chargeDeposit(
      b.Id
    );
    Test.stopTest();
    Assert.areEqual('Deposit Paid', s.guaranteeStatus, s.message);
    PMS_ExperienceTestFactory.num(800, s.depositPaid, 'deposit paid');
    Assert.isFalse(s.canChargeDeposit);
  }

  @isTest
  static void consolePlacesHold() {
    PMS_Booking__c b = withCard(
      booking(
        policy('Pre-authorisation'),
        Datetime.now().addDays(5),
        'Confirmed'
      )
    );
    Test.setMock(HttpCalloutMock.class, new StripeMock());
    Test.startTest();
    PMS_GuaranteeController.State s = PMS_GuaranteeController.placeHold(b.Id);
    Test.stopTest();
    Assert.areEqual('Authorized', s.holdStatus, s.message);
    Assert.isTrue(s.canCaptureHold);
  }

  @isTest
  static void consoleCapturesPartOfHold() {
    PMS_Booking__c b = withCard(
      booking(policy('Pre-authorisation'), Datetime.now().addDays(-1), 'Active')
    );
    PMS_GuaranteeTriggerHandler.bypass = true;
    update new PMS_Booking__c(
      Id = b.Id,
      Preauth_Intent_Id__c = 'pi_hold',
      Preauth_Status__c = 'Authorized',
      Preauth_Amount__c = 800
    );
    PMS_GuaranteeTriggerHandler.bypass = false;
    StripeMock mock = new StripeMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    PMS_GuaranteeController.State s = PMS_GuaranteeController.captureHold(
      b.Id,
      250
    );
    Test.stopTest();
    Assert.areEqual('Captured', s.holdStatus, s.message);
    Assert.isTrue(mock.sent('amount_to_capture=25000'));
    PMS_ExperienceTestFactory.num(
      250,
      [
        SELECT Amount__c
        FROM PMS_Payment__c
        WHERE Gateway_Reference__c = 'pi_hold'
      ]
      .Amount__c,
      'captured'
    );
    try {
      PMS_GuaranteeController.captureHold(b.Id, 100);
      Assert.fail('the hold is gone');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('no open hold'), e.getMessage());
    }
  }

  @isTest
  static void consoleReleasesHold() {
    PMS_Booking__c b = withCard(
      booking(policy('Pre-authorisation'), Datetime.now().addDays(-1), 'Active')
    );
    PMS_GuaranteeTriggerHandler.bypass = true;
    update new PMS_Booking__c(
      Id = b.Id,
      Preauth_Intent_Id__c = 'pi_hold',
      Preauth_Status__c = 'Authorized',
      Preauth_Amount__c = 800
    );
    PMS_GuaranteeTriggerHandler.bypass = false;
    Test.setMock(HttpCalloutMock.class, new StripeMock());
    Test.startTest();
    PMS_GuaranteeController.State s = PMS_GuaranteeController.captureHold(
      b.Id,
      0
    );
    Test.stopTest();
    Assert.areEqual('Released', s.holdStatus, s.message);
  }

  @isTest
  static void stripeClientHelpers() {
    Assert.areEqual(1235L, PMS_StripeClient.toMinor(12.345, 'sek'));
    Assert.areEqual(500L, PMS_StripeClient.toMinor(500, 'JPY'));
    PMS_ExperienceTestFactory.num(
      12.34,
      PMS_StripeClient.toMajor(1234, 'sek'),
      'sek'
    );
    Assert.isNull(PMS_StripeClient.toMajor(null, 'sek'));
    Assert.areEqual(
      'a=1',
      PMS_StripeClient.formEncode(
        new Map<String, String>{ 'a' => '1', 'b' => null }
      )
    );
    Assert.areEqual('abc...', PMS_GuaranteeService.cut('abcdefghij', 6));
  }
}
