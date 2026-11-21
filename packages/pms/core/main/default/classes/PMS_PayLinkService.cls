/**
 * Core entry point for the App Home "Stripe pay link" action.
 *
 * Online payments live in the PMS Experience package, which Core must not reference. This class
 * finds the Experience implementation (PMS_StripePayLinkProvider, a System.Callable) at runtime.
 * Invoice access and status checks happen in the provider, in the running user's context.
 *
 * Returns a map with url, amount, currencyCode, invoiceNumber and expiresAt.
 */
public with sharing class PMS_PayLinkService {
  /** Test-only hook: lets Core tests point the lookup at a missing or non-callable type. */
  @TestVisible
  private static String providerName = 'PMS_StripePayLinkProvider';
  private static final String NOT_INSTALLED = 'Online payments (PMS Experience) are not installed.';

  @AuraEnabled
  public static Object createInvoiceLink(Id invoiceId) {
    try {
      // Resolve in this package's namespace: a bare name from installed managed code can
      // resolve against the subscriber's namespace instead.
      String self = PMS_PayLinkService.class.getName();
      String ns = self.contains('.') ? self.substringBefore('.') : null;
      Type t = ns == null
        ? Type.forName(providerName)
        : Type.forName(ns, providerName);
      if (t == null) {
        throw new PMS_Exception(NOT_INSTALLED);
      }
      Object provider = t.newInstance();
      if (!(provider instanceof System.Callable)) {
        throw new PMS_Exception(NOT_INSTALLED);
      }
      return ((System.Callable) provider)
        .call(
          'createInvoiceLink',
          new Map<String, Object>{ 'invoiceId' => invoiceId }
        );
    } catch (Exception e) {
      AuraHandledException ex = new AuraHandledException(e.getMessage());
      ex.setMessage(e.getMessage());
      throw ex;
    }
  }
}
