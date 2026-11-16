@isTest
private class PMS_DunningTest {
  private class StripeMock implements HttpCalloutMock {
    public HttpRequest last;
    public HttpResponse respond(HttpRequest req) {
      last = req;
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        '{"id":"cs_test","url":"https://checkout.stripe.com/c/pay/cs_test"}'
      );
      return res;
    }
  }

  @TestSetup
  static void setup() {
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Webhook_Secret__c = 'whsec_test',
      Checkout_Return_URL__c = 'https://example.com/pay/PMS_PaymentComplete',
      Public_Pay_URL__c = 'https://example.my.salesforce-sites.com/pay'
    );
    insert new PMS_Dunning_Policy__c(
      Name = 'Default',
      Active__c = true,
      Is_Default__c = true,
      Reminder_1_Days__c = 5,
      Reminder_2_Days__c = 15,
      Plan_Offer_Days__c = 25,
      Collections_Days__c = 40,
      Min_Days_Between__c = 7,
      Minimum_Balance__c = 50,
      Consumer_Reminder_Fee__c = 60,
      Fee_In_Terms__c = false,
      Business_Late_Fee__c = 450,
      Charge_Interest__c = true,
      Reference_Rate__c = 2,
      Interest_Margin__c = 8,
      Plan_Instalments__c = 3,
      Plan_Grace_Days__c = 10,
      Sender_Name__c = 'Test Fastigheter AB',
      Payment_Instructions__c = 'Bankgiro 123-4567, reference: the invoice number.'
    );
  }

  private static PMS_Invoice__c invoice(
    String customerType,
    Integer daysOverdue,
    Id bookingId
  ) {
    Account a = new Account(
      Name = 'Debtor ' + customerType,
      PMS_Customer_Type__c = customerType
    );
    insert a;
    insert new Contact(
      AccountId = a.Id,
      LastName = 'Debtor',
      Email = 'debtor+' + a.Id + '@example.com'
    );
    PMS_Invoice__c inv = new PMS_Invoice__c(
      Account__c = a.Id,
      Booking__c = bookingId,
      Issue_Date__c = Date.today().addDays(-daysOverdue - 14),
      Due_Date__c = Date.today().addDays(-daysOverdue),
      Currency_Code__c = 'SEK',
      Status__c = 'Issued',
      Subtotal__c = 0,
      Tax_Total__c = 0,
      Amount_Paid__c = 0
    );
    insert inv;
    insert new PMS_Charge__c(
      Invoice__c = inv.Id,
      Account__c = a.Id,
      Booking__c = bookingId,
      Charge_Type__c = 'Rent',
      Description__c = 'Rent',
      Quantity__c = 1,
      Unit_Price__c = 1000,
      Tax_Rate__c = 0,
      Status__c = 'Invoiced',
      Service_Date__c = inv.Issue_Date__c
    );
    return inv;
  }

  private static PMS_Invoice__c reload(Id invoiceId) {
    return PMS_DunningService.load(new Set<Id>{ invoiceId })[0];
  }

  private static List<String> run(Id invoiceId) {
    return PMS_DunningService.process(
      new Set<Id>{ invoiceId },
      Date.today(),
      false
    );
  }

  private static Decimal lateCharges(Id invoiceId) {
    Decimal total = 0;
    for (PMS_Charge__c c : [
      SELECT Unit_Price__c
      FROM PMS_Charge__c
      WHERE Invoice__c = :invoiceId AND Charge_Type__c = 'Late Fee'
    ]) {
      total += c.Unit_Price__c;
    }
    return total;
  }

  // ---------------------------------------------------------------- steps and fees

  @isTest
  static void businessGetsReminderAndLateFeeFromBatch() {
    PMS_Invoice__c inv = invoice('Business', 30, null);
    Test.startTest();
    Database.executeBatch(new PMS_DunningBatch(), 20);
    Test.stopTest();
    PMS_Invoice__c after = reload(inv.Id);
    Assert.areEqual('Reminder 1', after.Dunning_Stage__c);
    Assert.areEqual('Overdue', after.Status__c);
    Assert.isTrue(after.Late_Fee_Posted__c);
    Assert.isNotNull(after.Pay_Key__c);
    PMS_TestDataFactory.num(450, lateCharges(inv.Id), 'business late fee');
    PMS_TestDataFactory.num(1450, after.Balance__c, 'balance with fee');
    PMS_Dunning_Event__c e = [
      SELECT Stage__c, Sent_To__c, Fee_Posted__c, Interest_Posted__c
      FROM PMS_Dunning_Event__c
      WHERE Invoice__c = :inv.Id
    ];
    Assert.areEqual('Reminder 1', e.Stage__c);
    Assert.areEqual(
      [SELECT Email FROM Contact WHERE AccountId = :after.Account__c LIMIT 1]
      .Email,
      e.Sent_To__c
    );
    PMS_TestDataFactory.num(
      0,
      e.Interest_Posted__c,
      'no interest on reminder 1'
    );
  }

  @isTest
  static void consumerFeeOnlyWhenAgreed() {
    PMS_Invoice__c noTerms = invoice('Consumer', 10, null);
    run(noTerms.Id);
    PMS_TestDataFactory.num(
      0,
      lateCharges(noTerms.Id),
      'no fee without agreement'
    );
    Assert.isTrue(reload(noTerms.Id).Late_Fee_Posted__c, 'decided once');

    PMS_Dunning_Policy__c p = [SELECT Id FROM PMS_Dunning_Policy__c LIMIT 1];
    p.Fee_In_Terms__c = true;
    update p;
    PMS_Invoice__c withTerms = invoice('Consumer', 10, null);
    run(withTerms.Id);
    PMS_TestDataFactory.num(
      60,
      lateCharges(withTerms.Id),
      'consumer reminder fee'
    );
  }

  @isTest
  static void stepsWaitForTheGapThenChargeInterest() {
    PMS_Invoice__c inv = invoice('Consumer', 30, null);
    run(inv.Id);
    Assert.areEqual('Reminder 1', reload(inv.Id).Dunning_Stage__c);
    run(inv.Id);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Dunning_Event__c WHERE Invoice__c = :inv.Id],
      'same week: no second letter'
    );

    update new PMS_Invoice__c(
      Id = inv.Id,
      Dunning_Last_Sent_At__c = Datetime.now().addDays(-8)
    );
    run(inv.Id);
    PMS_Invoice__c after = reload(inv.Id);
    Assert.areEqual('Reminder 2', after.Dunning_Stage__c);
    Assert.areEqual(Date.today(), after.Interest_Through__c);
    // 1000 x 10% x 30 / 365
    PMS_TestDataFactory.num(8.22, lateCharges(inv.Id), 'interest');
  }

  @isTest
  static void pausedAndSmallInvoicesAreLeftAlone() {
    PMS_Invoice__c paused = invoice('Consumer', 30, null);
    update new PMS_Invoice__c(Id = paused.Id, Dunning_Paused__c = true);
    run(paused.Id);
    Assert.isNull(reload(paused.Id).Dunning_Stage__c);

    PMS_Invoice__c notYet = invoice('Consumer', 2, null);
    run(notYet.Id);
    Assert.isNull(
      reload(notYet.Id).Dunning_Stage__c,
      'reminder 1 only after 5 days'
    );
    Assert.areEqual('Overdue', reload(notYet.Id).Status__c);
  }

  // ---------------------------------------------------------------- payment plans

  @isTest
  static void planOfferIsAcceptedByFirstInstalment() {
    PMS_Invoice__c inv = invoice('Consumer', 30, null);
    update new PMS_Invoice__c(
      Id = inv.Id,
      Dunning_Stage__c = 'Reminder 2',
      Dunning_Last_Sent_At__c = Datetime.now().addDays(-8),
      Late_Fee_Posted__c = true,
      Interest_Through__c = Date.today()
    );
    run(inv.Id);
    PMS_Invoice__c after = reload(inv.Id);
    Assert.areEqual('Plan Offered', after.Dunning_Stage__c);
    PMS_Payment_Plan__c plan = [
      SELECT
        Id,
        Status__c,
        Total__c,
        (SELECT Amount__c, Due_Date__c FROM Instalments__r ORDER BY Number__c)
      FROM PMS_Payment_Plan__c
      WHERE Invoice__c = :inv.Id
    ];
    Assert.areEqual('Proposed', plan.Status__c);
    Assert.areEqual(3, plan.Instalments__r.size());
    Decimal sum = 0;
    for (PMS_Payment_Plan_Instalment__c i : plan.Instalments__r) {
      sum += i.Amount__c;
    }
    PMS_TestDataFactory.num(plan.Total__c, sum, 'instalments add up');
    PMS_TestDataFactory.num(
      333,
      plan.Instalments__r[0].Amount__c,
      'first instalment'
    );

    insert new PMS_Payment__c(
      Invoice__c = inv.Id,
      Account__c = inv.Account__c,
      Amount__c = 333,
      Payment_Type__c = 'Payment',
      Method__c = 'Card',
      Status__c = 'Succeeded',
      Received_Date__c = Date.today(),
      Gateway_Reference__c = 'pi_inst1'
    );
    run(inv.Id);
    Assert.areEqual(
      'Active',
      [SELECT Status__c FROM PMS_Payment_Plan__c WHERE Id = :plan.Id].Status__c
    );
    Assert.areEqual('Payment Plan', reload(inv.Id).Dunning_Stage__c);
    Assert.areEqual(
      'Paid',
      [
        SELECT Status__c
        FROM PMS_Payment_Plan_Instalment__c
        WHERE Plan__c = :plan.Id AND Number__c = 1
      ]
      .Status__c
    );
  }

  @isTest
  static void brokenPlanGoesToCollectionsWithLeaseTasks() {
    PMS_TestDataFactory.Property prop = PMS_TestDataFactory.property();
    PMS_Booking__c lease = new PMS_Booking__c(
      RecordTypeId = PMS_TestDataFactory.rt(
        PMS_Booking__c.SObjectType,
        'Lease'
      ),
      Site__c = prop.site.Id,
      Space__c = prop.unit.Id,
      Account__c = prop.tenant.Id,
      Start__c = Datetime.now().addMonths(-6),
      End__c = Datetime.now().addMonths(6),
      Status__c = 'Active',
      Lease_Type__c = 'Residential',
      Total_Amount__c = 9000
    );
    insert lease;
    PMS_Invoice__c inv = invoice('Consumer', 60, lease.Id);
    PMS_Dunning_Policy__c p = [SELECT Id FROM PMS_Dunning_Policy__c LIMIT 1];
    p.Collections_Agency_Email__c = 'cases@inkasso.example.com';
    update p;
    PMS_Payment_Plan__c plan = new PMS_Payment_Plan__c(
      Invoice__c = inv.Id,
      Account__c = inv.Account__c,
      Status__c = 'Active',
      Total__c = 1000,
      Paid_At_Start__c = 0
    );
    insert plan;
    insert new PMS_Payment_Plan_Instalment__c(
      Plan__c = plan.Id,
      Number__c = 1,
      Due_Date__c = Date.today().addDays(-20),
      Amount__c = 500,
      Status__c = 'Due'
    );
    update new PMS_Invoice__c(
      Id = inv.Id,
      Dunning_Stage__c = 'Payment Plan',
      Late_Fee_Posted__c = true,
      Dunning_Last_Sent_At__c = Datetime.now().addDays(-30)
    );

    run(inv.Id);
    Assert.areEqual(
      'Broken',
      [SELECT Status__c FROM PMS_Payment_Plan__c WHERE Id = :plan.Id].Status__c
    );
    Assert.areEqual('Plan Offered', reload(inv.Id).Dunning_Stage__c);

    run(inv.Id);
    PMS_Invoice__c after = reload(inv.Id);
    Assert.areEqual('Collections', after.Dunning_Stage__c);
    List<Task> tasks = [SELECT Subject FROM Task ORDER BY Subject];
    Assert.areEqual(
      2,
      tasks.size(),
      'hand-over task and residential termination task'
    );
    Assert.isTrue(tasks[0].Subject.startsWith('Hand over'), tasks[0].Subject);
    Assert.isTrue(tasks[1].Subject.contains('termination'), tasks[1].Subject);
    Assert.isNull(
      PMS_DunningService.nextStep(
        after,
        PMS_DunningService.policiesFor(new List<PMS_Invoice__c>{ after })
          .get(after.Id),
        Date.today(),
        true
      ),
      'nothing after collections'
    );
  }

  // ---------------------------------------------------------------- pay link

  private static RestResponse get(String invoiceId, String key) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/pms/pay';
    req.httpMethod = 'GET';
    if (invoiceId != null) {
      req.params.put('i', invoiceId);
    }
    if (key != null) {
      req.params.put('k', key);
    }
    RestContext.request = req;
    RestContext.response = new RestResponse();
    PMS_PayLinkRest.open();
    return RestContext.response;
  }

  @isTest
  static void payLinkRedirectsToStripe() {
    PMS_Invoice__c inv = invoice('Consumer', 10, null);
    run(inv.Id);
    PMS_Invoice__c after = reload(inv.Id);
    Assert.isTrue(
      PMS_DunningService.payUrl(inv.Id, after.Pay_Key__c)
        .startsWith(
          'https://example.my.salesforce-sites.com/pay/services/apexrest/pms/pay?i='
        )
    );
    StripeMock mock = new StripeMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    RestResponse ok = get(inv.Id, after.Pay_Key__c);
    Test.stopTest();
    Assert.areEqual(302, ok.statusCode);
    Assert.areEqual(
      'https://checkout.stripe.com/c/pay/cs_test',
      ok.headers.get('Location')
    );
    String body = EncodingUtil.urlDecode(mock.last.getBody(), 'UTF-8');
    Assert.isTrue(body.contains('metadata[invoiceNumber]=' + after.Name), body);
    Assert.areEqual(
      '100000',
      body.substringAfter('unit_amount]=').substringBefore('&'),
      body
    );

    Assert.areEqual(404, get(inv.Id, 'wrongwrongwrongwrong').statusCode);
    Assert.areEqual(404, get('not-an-id', after.Pay_Key__c).statusCode);
    Assert.areEqual(404, get(null, null).statusCode);
  }

  @isTest
  static void payLinkForPaidInvoiceSaysThankYou() {
    PMS_Invoice__c inv = invoice('Consumer', 10, null);
    update new PMS_Invoice__c(
      Id = inv.Id,
      Pay_Key__c = 'abcdefabcdefabcdefabcdef'
    );
    insert new PMS_Payment__c(
      Invoice__c = inv.Id,
      Account__c = inv.Account__c,
      Amount__c = 1000,
      Payment_Type__c = 'Payment',
      Method__c = 'Card',
      Status__c = 'Succeeded',
      Received_Date__c = Date.today(),
      Gateway_Reference__c = 'pi_paid'
    );
    RestResponse res = get(inv.Id, 'abcdefabcdefabcdefabcdef');
    Assert.areEqual(200, res.statusCode);
    Assert.isTrue(res.responseBody.toString().contains('Already paid'));
  }

  // ---------------------------------------------------------------- console, batch, rules

  @isTest
  static void consoleActions() {
    PMS_Invoice__c inv = invoice('Consumer', 10, null);
    PMS_DunningController.State s = PMS_DunningController.getState(inv.Id);
    Assert.isTrue(s.hasPolicy);
    Assert.areEqual('Reminder 1', s.nextStep);
    Assert.isTrue(s.canSendNow);

    s = PMS_DunningController.pause(inv.Id, 'Customer disputes the amount');
    Assert.isTrue(s.paused);
    try {
      PMS_DunningController.sendNext(inv.Id);
      Assert.fail('paused invoices cannot be sent');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('paused'), e.getMessage());
    }
    s = PMS_DunningController.resume(inv.Id);
    Assert.isFalse(s.paused);

    s = PMS_DunningController.sendNext(inv.Id);
    Assert.areEqual('Reminder 1', s.stage);
    s = PMS_DunningController.offerPlan(inv.Id, 4);
    Assert.areEqual('Proposed', s.planStatus);
    Assert.areEqual(4, s.instalments.size());
    Assert.isTrue(
      s.events.size() >= 3,
      'paused, resumed, reminder 1, plan offered'
    );
    try {
      PMS_DunningController.offerPlan(inv.Id, 3);
      Assert.fail('only one open plan');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('already open'), e.getMessage());
    }
  }

  @isTest
  static void rulesAndSchedule() {
    PMS_Dunning_Policy__c p = new PMS_Dunning_Policy__c(
      Reminder_1_Days__c = 5,
      Reminder_2_Days__c = 15,
      Plan_Offer_Days__c = null,
      Collections_Days__c = 40,
      Charge_Interest__c = true,
      Reference_Rate__c = 2,
      Interest_Margin__c = 8
    );
    Map<String, Object> m = new Map<String, Object>{
      'attributes' => new Map<String, Object>{ 'type' => 'PMS_Invoice__c' },
      'Balance__c' => 2000,
      'Status__c' => 'Overdue',
      'Due_Date__c' => Date.today().addDays(-41),
      'Dunning_Stage__c' => 'Reminder 2'
    };
    PMS_Invoice__c inv = (PMS_Invoice__c) JSON.deserialize(
      JSON.serialize(m),
      PMS_Invoice__c.class
    );
    Assert.areEqual(
      'Collections',
      PMS_DunningService.nextStep(inv, p, Date.today(), false),
      'plan offer switched off: straight to collections'
    );
    PMS_TestDataFactory.num(
      22.47,
      PMS_DunningService.interestFor(inv, p, 0, Date.today()),
      '2000 x 10% x 41/365'
    );
    PMS_TestDataFactory.num(
      17.52,
      PMS_DunningService.interestFor(inv, p, 440, Date.today()),
      'fees excluded from the principal'
    );
    Assert.isNull(PMS_DunningService.nextStep(inv, null, Date.today(), false));

    String jobId = System.schedule(
      'PMS Dunning test',
      '0 1 13 * * ?',
      new PMS_DunningBatch()
    );
    Assert.isNotNull(jobId);
    Assert.areEqual('abc...', PMS_DunningService.cut('abcdefgh', 6));
  }
}
