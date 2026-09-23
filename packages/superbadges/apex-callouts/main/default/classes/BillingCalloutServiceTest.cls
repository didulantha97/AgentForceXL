@IsTest
private class BillingCalloutServiceTest {
  @TestSetup
  static void createProjects() {
    insert new List<Accessibility_Project__c>{
      new Accessibility_Project__c(
        Amount__c = 250,
        Type__c = 'Sign Language Interpreters',
        Status__c = 'Submitted'
      ),
      new Accessibility_Project__c(
        Amount__c = 375,
        Type__c = 'Sign Language Interpreters',
        Status__c = 'Submitted'
      ),
      new Accessibility_Project__c(
        Amount__c = 500,
        Type__c = 'Sign Language Interpreters',
        Status__c = 'Submitted'
      )
    };
  }

  @IsTest
  static void proxyReturnsSoapResponse() {
    Test.setMock(WebServiceMock.class, new BillingCalloutServiceMock('ok'));

    Accessibility_Project__c projectRecord = [
      SELECT Id, Amount__c
      FROM Accessibility_Project__c
      ORDER BY Amount__c
      LIMIT 1
    ];
    BillingServiceProxy.project project = new BillingServiceProxy.project();
    project.username = 'mock-user';
    project.password = 'mock-password';
    project.projectid = projectRecord.Id;
    project.billAmount = Double.valueOf(projectRecord.Amount__c);

    Test.startTest();
    String status = new BillingServiceProxy.InvoicesPortSoap11()
      .billProject(project);
    Test.stopTest();

    System.assertEquals(
      'ok',
      status,
      'The proxy must return the status supplied by the SOAP service.'
    );
  }

  @IsTest
  static void successfulBillingCompletesProject() {
    Accessibility_Project__c projectRecord = getProjectByAmount(250);
    Test.setMock(WebServiceMock.class, new BillingCalloutServiceMock('OK'));

    Test.startTest();
    AccessibilityProjectBilling.callBillingService(
      projectRecord.Id,
      projectRecord.Amount__c
    );
    Test.stopTest();

    projectRecord = [
      SELECT Status__c
      FROM Accessibility_Project__c
      WHERE Id = :projectRecord.Id
    ];
    System.assertEquals(
      'Complete',
      projectRecord.Status__c,
      'A successful billing response must complete the project.'
    );
  }

  @IsTest
  static void rejectedBillingLeavesProjectSubmitted() {
    Accessibility_Project__c projectRecord = getProjectByAmount(375);
    Test.setMock(WebServiceMock.class, new BillingCalloutServiceMock('ERROR'));

    Test.startTest();
    AccessibilityProjectBilling.callBillingService(
      projectRecord.Id,
      projectRecord.Amount__c
    );
    Test.stopTest();

    projectRecord = [
      SELECT Status__c
      FROM Accessibility_Project__c
      WHERE Id = :projectRecord.Id
    ];
    System.assertEquals(
      'Submitted',
      projectRecord.Status__c,
      'A rejected billing response must not complete the project.'
    );
  }

  @IsTest
  static void serviceFailureLeavesProjectSubmitted() {
    Accessibility_Project__c projectRecord = getProjectByAmount(500);
    Test.setMock(
      WebServiceMock.class,
      new BillingCalloutServiceMock(null, true)
    );

    Test.startTest();
    AccessibilityProjectBilling.callBillingService(
      projectRecord.Id,
      projectRecord.Amount__c
    );
    Test.stopTest();

    projectRecord = [
      SELECT Status__c
      FROM Accessibility_Project__c
      WHERE Id = :projectRecord.Id
    ];
    System.assertEquals(
      'Submitted',
      projectRecord.Status__c,
      'A SOAP fault must not change project data.'
    );
  }

  private static Accessibility_Project__c getProjectByAmount(Decimal amount) {
    return [
      SELECT Id, Amount__c, Status__c
      FROM Accessibility_Project__c
      WHERE Amount__c = :amount
      LIMIT 1
    ];
  }
}
