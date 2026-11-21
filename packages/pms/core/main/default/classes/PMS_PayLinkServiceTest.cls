@isTest
private class PMS_PayLinkServiceTest {
  static String lastAction;
  static Map<String, Object> lastArgs;

  /** Stands in for the Experience provider: records the call and returns a result map. */
  public class EchoProvider implements System.Callable {
    public Object call(String action, Map<String, Object> args) {
      lastAction = action;
      lastArgs = args;
      return new Map<String, Object>{
        'url' => 'https://pay.example.com/x',
        'invoiceNumber' => 'INV-1'
      };
    }
  }

  public class FailingProvider implements System.Callable {
    public Object call(String action, Map<String, Object> args) {
      throw new PMS_Exception('Invoice is a draft.');
    }
  }

  private static void assertAura(Id invoiceId, String expectedFragment) {
    try {
      PMS_PayLinkService.createInvoiceLink(invoiceId);
      Assert.fail('Expected an AuraHandledException');
    } catch (AuraHandledException e) {
      Assert.isTrue(
        e.getMessage().contains(expectedFragment),
        'Unexpected message: ' + e.getMessage()
      );
    }
  }

  @isTest
  static void missingProviderReportsNotInstalled() {
    PMS_PayLinkService.providerName = 'PMS_DoesNotExist_Provider';
    Test.startTest();
    assertAura(null, 'not installed');
    Test.stopTest();
  }

  @isTest
  static void nonCallableProviderReportsNotInstalled() {
    // PMS_TriggerBypass exists and can be instantiated, but is not a System.Callable.
    PMS_PayLinkService.providerName = 'PMS_TriggerBypass';
    Test.startTest();
    assertAura(null, 'not installed');
    Test.stopTest();
  }

  @isTest
  static void callsProviderWithActionAndInvoiceId() {
    Account a = PMS_TestDataFactory.account('Pay Link Co');
    PMS_Invoice__c inv = new PMS_Invoice__c(
      Account__c = a.Id,
      Issue_Date__c = Date.today(),
      Due_Date__c = Date.today().addDays(14),
      Status__c = 'Issued'
    );
    insert inv;
    PMS_PayLinkService.providerName = 'PMS_PayLinkServiceTest.EchoProvider';
    Test.startTest();
    Object r = PMS_PayLinkService.createInvoiceLink(inv.Id);
    Test.stopTest();
    Assert.areEqual('createInvoiceLink', lastAction);
    Assert.areEqual(inv.Id, lastArgs.get('invoiceId'));
    Map<String, Object> m = (Map<String, Object>) r;
    Assert.areEqual('https://pay.example.com/x', m.get('url'));
    Assert.areEqual('INV-1', m.get('invoiceNumber'));
  }

  @isTest
  static void providerErrorsSurfaceAsAuraHandledException() {
    PMS_PayLinkService.providerName = 'PMS_PayLinkServiceTest.FailingProvider';
    Test.startTest();
    assertAura(null, 'Invoice is a draft.');
    Test.stopTest();
  }
}
