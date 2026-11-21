@isTest
private class PMS_StripePayLinkProviderTest {
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

  private static final String OK_BODY = '{"id":"cs_test_1","url":"https://checkout.stripe.com/c/pay/cs_test_1","expires_at":1893456000}';

  @TestSetup
  static void setup() {
    PMS_ExperienceTestFactory.grantPmsAccess(
      new List<String>{ 'PMS_Core_Admin', 'PMS_Stripe_Access' }
    );
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Checkout_Return_URL__c = 'https://example.com/pay/PMS_PaymentComplete'
    );
    Account a = PMS_ExperienceTestFactory.account('Pay Link Customer');
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
    return [SELECT Id, Name, Status__c, Balance__c FROM PMS_Invoice__c LIMIT 1];
  }

  private static Object callProvider(Id invoiceId) {
    return new PMS_StripePayLinkProvider()
      .call(
        'createInvoiceLink',
        new Map<String, Object>{ 'invoiceId' => invoiceId }
      );
  }

  /** The provider throws PMS_Exception; Core's PMS_PayLinkService wraps it (covered in core tests). */
  private static void assertProviderError(Id invoiceId, String fragment) {
    try {
      callProvider(invoiceId);
      Assert.fail('Expected a PMS_Exception');
    } catch (PMS_Exception e) {
      Assert.isTrue(
        e.getMessage().contains(fragment),
        'Unexpected message: ' + e.getMessage()
      );
    }
  }

  @isTest
  static void providerReturnsLinkMap() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      PMS_Invoice__c inv = invoice();
      StripeMock mock = new StripeMock(200, OK_BODY);
      Test.setMock(HttpCalloutMock.class, mock);
      Test.startTest();
      Map<String, Object> r = (Map<String, Object>) callProvider(inv.Id);
      Test.stopTest();
      Assert.areEqual(
        'https://checkout.stripe.com/c/pay/cs_test_1',
        r.get('url')
      );
      Assert.areEqual(inv.Name, r.get('invoiceNumber'));
      Assert.areEqual('SEK', r.get('currencyCode'));
      PMS_ExperienceTestFactory.num(1000, (Decimal) r.get('amount'), 'amount');
      Assert.isNotNull(r.get('expiresAt'));
      Assert.isTrue(
        mock.last.getEndpoint().endsWith('/v1/checkout/sessions'),
        mock.last.getEndpoint()
      );
    }
  }

  @isTest
  static void providerCalledDirectlyReturnsSameKeys() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.setMock(HttpCalloutMock.class, new StripeMock(200, OK_BODY));
      Test.startTest();
      Object o = new PMS_StripePayLinkProvider()
        .call(
          'createInvoiceLink',
          new Map<String, Object>{ 'invoiceId' => invoice().Id }
        );
      Test.stopTest();
      Map<String, Object> r = (Map<String, Object>) o;
      Assert.areEqual(
        new Set<String>{
          'url',
          'amount',
          'currencyCode',
          'invoiceNumber',
          'expiresAt'
        },
        r.keySet()
      );
    }
  }

  @isTest
  static void unknownActionThrowsIllegalArgument() {
    try {
      new PMS_StripePayLinkProvider()
        .call('refundEverything', new Map<String, Object>());
      Assert.fail('Expected an IllegalArgumentException');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(
        e.getMessage().contains('Unknown action: refundEverything'),
        e.getMessage()
      );
    }
  }

  @isTest
  static void draftInvoiceIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      PMS_Invoice__c inv = invoice();
      update new PMS_Invoice__c(Id = inv.Id, Status__c = 'Draft');
      Test.startTest();
      assertProviderError(inv.Id, 'can\'t be paid while its status is Draft');
      Test.stopTest();
    }
  }

  @isTest
  static void voidInvoiceIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      PMS_Invoice__c inv = invoice();
      update new PMS_Invoice__c(Id = inv.Id, Status__c = 'Void');
      Test.startTest();
      assertProviderError(inv.Id, 'can\'t be paid while its status is Void');
      Test.stopTest();
    }
  }

  @isTest
  static void zeroBalanceInvoiceIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account a = PMS_ExperienceTestFactory.account('Zero Balance Co');
      PMS_Invoice__c zero = new PMS_Invoice__c(
        Account__c = a.Id,
        Issue_Date__c = Date.today(),
        Due_Date__c = Date.today().addDays(14),
        Currency_Code__c = 'SEK',
        Status__c = 'Issued'
      );
      insert zero;
      Test.startTest();
      assertProviderError(zero.Id, 'nothing left to pay');
      Test.stopTest();
    }
  }

  @isTest
  static void missingInvoiceIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.startTest();
      assertProviderError(null, 'Invoice not found');
      Test.stopTest();
    }
  }

  @isTest
  static void stripeFailureSurfacesAsPmsException() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.setMock(
        HttpCalloutMock.class,
        new StripeMock(400, '{"error":{"message":"Invalid API Key provided"}}')
      );
      Test.startTest();
      assertProviderError(invoice().Id, 'Invalid API Key provided');
      Test.stopTest();
    }
  }
}
