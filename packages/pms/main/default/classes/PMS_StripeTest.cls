@isTest
private class PMS_StripeTest {
  private static final String SECRET = 'whsec_test_secret';

  @TestSetup
  static void setup() {
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Webhook_Secret__c = SECRET,
      Checkout_Return_URL__c = 'https://example.com/pay/PMS_PaymentComplete'
    );
    Account a = PMS_TestDataFactory.account('Stripe Customer');
    PMS_Invoice__c inv = new PMS_Invoice__c(
      Account__c = a.Id,
      Issue_Date__c = Date.today(),
      Due_Date__c = Date.today().addDays(14),
      Currency_Code__c = 'SEK',
      Status__c = 'Issued'
    );
    insert inv;
    insert new PMS_Charge__c(
      Invoice__c = inv.Id,
      Account__c = a.Id,
      Charge_Type__c = 'Other',
      Description__c = 'Test charge',
      Quantity__c = 1,
      Unit_Price__c = 1000,
      Tax_Rate__c = 0,
      Status__c = 'Invoiced'
    );
  }

  private static PMS_Invoice__c invoice() {
    return [
      SELECT Id, Name, Status__c, Amount_Paid__c, Balance__c
      FROM PMS_Invoice__c
      LIMIT 1
    ];
  }

  private static String checkoutEvent(
    String type,
    String pi,
    Integer amountMinor,
    String paymentStatus,
    String invoiceNumber
  ) {
    return JSON.serialize(
      new Map<String, Object>{
        'id' => 'evt_' + type,
        'type' => type,
        'created' => Datetime.now().getTime() / 1000,
        'data' => new Map<String, Object>{
          'object' => new Map<String, Object>{
            'id' => 'cs_test_1',
            'object' => 'checkout.session',
            'payment_intent' => pi,
            'amount_total' => amountMinor,
            'currency' => 'sek',
            'payment_status' => paymentStatus,
            'metadata' => new Map<String, Object>{
              'invoiceNumber' => invoiceNumber
            }
          }
        }
      }
    );
  }

  private static String refundEvent(String pi, Integer refundedMinor) {
    return JSON.serialize(
      new Map<String, Object>{
        'id' => 'evt_refund',
        'type' => 'charge.refunded',
        'created' => Datetime.now().getTime() / 1000,
        'data' => new Map<String, Object>{
          'object' => new Map<String, Object>{
            'id' => 'ch_test_1',
            'object' => 'charge',
            'payment_intent' => pi,
            'amount_refunded' => refundedMinor,
            'currency' => 'sek'
          }
        }
      }
    );
  }

  private static String signatureFor(String body) {
    String ts = String.valueOf(Datetime.now().getTime() / 1000);
    return 't=' + ts + ',v1=' + PMS_StripeWebhook.sign(ts + '.' + body, SECRET);
  }

  private static RestResponse post(String body, String signature) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/pms/stripe';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body);
    if (signature != null) {
      req.headers.put('Stripe-Signature', signature);
    }
    RestContext.request = req;
    RestContext.response = new RestResponse();
    PMS_StripeWebhook.receive();
    return RestContext.response;
  }

  private static RestResponse postSigned(String body) {
    return post(body, signatureFor(body));
  }

  @isTest
  static void checkoutCompletedPaysInvoice() {
    PMS_Invoice__c inv = invoice();
    Test.startTest();
    RestResponse res = postSigned(
      checkoutEvent(
        'checkout.session.completed',
        'pi_1',
        100000,
        'paid',
        inv.Name
      )
    );
    Test.stopTest();

    Assert.areEqual(200, res.statusCode, res.responseBody.toString());
    PMS_Payment__c p = [
      SELECT Amount__c, Status__c, Invoice__c, Payment_Type__c, Method__c
      FROM PMS_Payment__c
      WHERE Gateway_Reference__c = 'pi_1'
    ];
    PMS_TestDataFactory.num(1000, p.Amount__c, 'amount');
    Assert.areEqual('Succeeded', p.Status__c);
    Assert.areEqual(inv.Id, p.Invoice__c);
    Assert.areEqual('Payment', p.Payment_Type__c);
    Assert.areEqual('Paid', invoice().Status__c);
  }

  @isTest
  static void retriesDoNotDoubleCount() {
    PMS_Invoice__c inv = invoice();
    String body = checkoutEvent(
      'checkout.session.completed',
      'pi_2',
      50000,
      'paid',
      inv.Name
    );
    Test.startTest();
    postSigned(body);
    postSigned(body);
    Test.stopTest();
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Payment__c WHERE Gateway_Reference__c = 'pi_2']
    );
    PMS_TestDataFactory.num(500, invoice().Amount_Paid__c, 'amount paid');
  }

  @isTest
  static void delayedPaymentPendingThenSucceeded() {
    PMS_Invoice__c inv = invoice();
    Test.startTest();
    postSigned(
      checkoutEvent(
        'checkout.session.completed',
        'pi_3',
        100000,
        'unpaid',
        inv.Name
      )
    );
    Assert.areEqual(
      'Pending',
      [SELECT Status__c FROM PMS_Payment__c WHERE Gateway_Reference__c = 'pi_3']
      .Status__c
    );
    postSigned(
      checkoutEvent(
        'checkout.session.async_payment_succeeded',
        'pi_3',
        100000,
        'paid',
        inv.Name
      )
    );
    Test.stopTest();
    Assert.areEqual(
      'Succeeded',
      [SELECT Status__c FROM PMS_Payment__c WHERE Gateway_Reference__c = 'pi_3']
      .Status__c
    );
  }

  @isTest
  static void lateFailureNeverUndoesSuccess() {
    PMS_Invoice__c inv = invoice();
    Test.startTest();
    postSigned(
      checkoutEvent(
        'checkout.session.completed',
        'pi_4',
        100000,
        'paid',
        inv.Name
      )
    );
    RestResponse res = postSigned(
      checkoutEvent(
        'checkout.session.async_payment_failed',
        'pi_4',
        100000,
        'unpaid',
        inv.Name
      )
    );
    Test.stopTest();
    Assert.areEqual(200, res.statusCode);
    Assert.areEqual(
      'Succeeded',
      [SELECT Status__c FROM PMS_Payment__c WHERE Gateway_Reference__c = 'pi_4']
      .Status__c
    );
  }

  @isTest
  static void asyncFailureRecordsFailedPayment() {
    PMS_Invoice__c inv = invoice();
    Test.startTest();
    postSigned(
      checkoutEvent(
        'checkout.session.async_payment_failed',
        'pi_5',
        100000,
        'unpaid',
        inv.Name
      )
    );
    Test.stopTest();
    Assert.areEqual(
      'Failed',
      [SELECT Status__c FROM PMS_Payment__c WHERE Gateway_Reference__c = 'pi_5']
      .Status__c
    );
    PMS_TestDataFactory.num(0, invoice().Amount_Paid__c, 'amount paid');
  }

  @isTest
  static void refundsReduceAmountPaid() {
    PMS_Invoice__c inv = invoice();
    Test.startTest();
    postSigned(
      checkoutEvent(
        'checkout.session.completed',
        'pi_6',
        100000,
        'paid',
        inv.Name
      )
    );
    postSigned(refundEvent('pi_6', 30000));
    postSigned(refundEvent('pi_6', 40000)); // second partial refund: Stripe sends the running total
    Test.stopTest();
    PMS_Payment__c r = [
      SELECT Amount__c, Payment_Type__c, Invoice__c
      FROM PMS_Payment__c
      WHERE Gateway_Reference__c = 'refund:ch_test_1'
    ];
    PMS_TestDataFactory.num(400, r.Amount__c, 'refund amount');
    Assert.areEqual('Refund', r.Payment_Type__c);
    Assert.areEqual(inv.Id, r.Invoice__c);
    PMS_TestDataFactory.num(
      600,
      invoice().Amount_Paid__c,
      'amount paid after refund'
    );
  }

  @isTest
  static void refundForUnknownPaymentIsRejected() {
    Test.startTest();
    RestResponse res = postSigned(refundEvent('pi_unknown', 1000));
    Test.stopTest();
    Assert.areEqual(400, res.statusCode);
  }

  @isTest
  static void unknownInvoiceIsRejected() {
    Test.startTest();
    RestResponse res = postSigned(
      checkoutEvent(
        'checkout.session.completed',
        'pi_7',
        1000,
        'paid',
        'INV-NOPE'
      )
    );
    Test.stopTest();
    Assert.areEqual(400, res.statusCode);
    Assert.areEqual(0, [SELECT COUNT() FROM PMS_Payment__c]);
  }

  @isTest
  static void otherEventsAreIgnored() {
    String body = JSON.serialize(
      new Map<String, Object>{
        'type' => 'customer.created',
        'data' => new Map<String, Object>{
          'object' => new Map<String, Object>{ 'id' => 'cus_1' }
        }
      }
    );
    Test.startTest();
    RestResponse res = postSigned(body);
    Test.stopTest();
    Assert.areEqual(200, res.statusCode);
    Assert.isTrue(res.responseBody.toString().contains('ignored'));
  }

  @isTest
  static void badSignaturesAreRejected() {
    PMS_Invoice__c inv = invoice();
    String body = checkoutEvent(
      'checkout.session.completed',
      'pi_8',
      1000,
      'paid',
      inv.Name
    );
    Test.startTest();
    Assert.areEqual(401, post(body, null).statusCode, 'missing header');
    Assert.areEqual(
      401,
      post(body, 't=123,v1=deadbeef').statusCode,
      'wrong signature'
    );
    Assert.areEqual(
      401,
      post(body + ' ', signatureFor(body)).statusCode,
      'tampered body'
    );
    Assert.areEqual(401, post(body, 'garbage').statusCode, 'malformed header');
    Test.stopTest();
    Assert.areEqual(0, [SELECT COUNT() FROM PMS_Payment__c]);
  }

  @isTest
  static void staleTimestampsAreRejected() {
    PMS_Invoice__c inv = invoice();
    String body = checkoutEvent(
      'checkout.session.completed',
      'pi_9',
      1000,
      'paid',
      inv.Name
    );
    String signature = signatureFor(body);
    PMS_StripeWebhook.clockOverride =
      Datetime.now().getTime() / 1000 +
      PMS_StripeWebhook.TOLERANCE_SECONDS +
      60;
    Test.startTest();
    Assert.areEqual(401, post(body, signature).statusCode);
    Test.stopTest();
  }

  @isTest
  static void amountConversion() {
    PMS_TestDataFactory.num(
      12.34,
      PMS_StripeWebhook.toMajor(1234, 'sek'),
      'sek'
    );
    PMS_TestDataFactory.num(
      1234,
      PMS_StripeWebhook.toMajor(1234, 'JPY'),
      'jpy'
    );
    Assert.isNull(PMS_StripeWebhook.toMajor(null, 'sek'));
    Assert.areEqual(1235L, PMS_StripeCheckout.toMinor(12.345, 'sek'));
    Assert.areEqual(500L, PMS_StripeCheckout.toMinor(500, 'jpy'));
  }

  // ---------------------------------------------------------------- checkout links

  private class StripeMock implements HttpCalloutMock {
    Integer status;
    String body;
    HttpRequest last;
    StripeMock(Integer status, String body) {
      this.status = status;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      last = req;
      HttpResponse res = new HttpResponse();
      res.setStatusCode(status);
      res.setBody(body);
      return res;
    }
  }

  @isTest
  static void createsCheckoutLinkForBalance() {
    PMS_Invoice__c inv = invoice();
    StripeMock mock = new StripeMock(
      200,
      '{"id":"cs_test_1","url":"https://checkout.stripe.com/c/pay/cs_test_1","expires_at":1893456000}'
    );
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    PMS_StripeCheckout.Result r = PMS_StripeCheckout.createInvoiceLink(inv.Id);
    Test.stopTest();
    Assert.areEqual('https://checkout.stripe.com/c/pay/cs_test_1', r.url);
    Assert.areEqual('SEK', r.currencyCode);
    Assert.isNotNull(r.expiresAt);
    Assert.areEqual(
      'callout:Stripe_API/v1/checkout/sessions',
      mock.last.getEndpoint()
    );
    String sent = EncodingUtil.urlDecode(mock.last.getBody(), 'UTF-8');
    Assert.isTrue(
      sent.contains('line_items[0][price_data][unit_amount]=100000'),
      sent
    );
    Assert.isTrue(sent.contains('metadata[invoiceNumber]=' + inv.Name), sent);
    Assert.isTrue(
      sent.contains('payment_intent_data[metadata][invoiceNumber]=' + inv.Name),
      sent
    );
    Assert.isTrue(sent.contains('status=paid'), sent);
  }

  @isTest
  static void invocableReturnsLinks() {
    Test.setMock(
      HttpCalloutMock.class,
      new StripeMock(200, '{"url":"https://checkout.stripe.com/c/pay/cs_2"}')
    );
    Test.startTest();
    List<String> urls = PMS_StripeCheckout.createLinks(
      new List<Id>{ invoice().Id }
    );
    Test.stopTest();
    Assert.areEqual('https://checkout.stripe.com/c/pay/cs_2', urls[0]);
  }

  @isTest
  static void stripeErrorsAreReadable() {
    Test.setMock(
      HttpCalloutMock.class,
      new StripeMock(400, '{"error":{"message":"Invalid API Key provided"}}')
    );
    Test.startTest();
    try {
      PMS_StripeCheckout.createInvoiceLink(invoice().Id);
      Assert.fail('expected an error');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('Invalid API Key'), e.getMessage());
    }
    Test.stopTest();
  }

  @isTest
  static void nonJsonResponseIsReadable() {
    Test.setMock(
      HttpCalloutMock.class,
      new StripeMock(502, '<html>Bad gateway</html>')
    );
    Test.startTest();
    try {
      PMS_StripeCheckout.createForInvoice(invoice().Id);
      Assert.fail('expected an error');
    } catch (PMS_Exception e) {
      Assert.isTrue(e.getMessage().contains('502'), e.getMessage());
    }
    Test.stopTest();
  }

  @isTest
  static void paidInvoiceCannotGetALink() {
    PMS_Invoice__c inv = invoice();
    postSigned(
      checkoutEvent(
        'checkout.session.completed',
        'pi_10',
        100000,
        'paid',
        inv.Name
      )
    );
    Test.startTest();
    try {
      PMS_StripeCheckout.createForInvoice(inv.Id);
      Assert.fail('expected an error');
    } catch (PMS_Exception e) {
      Assert.isTrue(
        e.getMessage().contains('nothing left to pay'),
        e.getMessage()
      );
    }
    Test.stopTest();
  }

  @isTest
  static void missingReturnUrlIsExplained() {
    PMS_Settings__c s = PMS_Settings__c.getOrgDefaults();
    s.Checkout_Return_URL__c = null;
    update s;
    Test.startTest();
    try {
      PMS_StripeCheckout.createForInvoice(invoice().Id);
      Assert.fail('expected an error');
    } catch (PMS_Exception e) {
      Assert.isTrue(
        e.getMessage().contains('Checkout Return URL'),
        e.getMessage()
      );
    }
    Test.stopTest();
  }
}
