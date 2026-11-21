/**
 * Experience implementation behind Core's PMS_PayLinkService (found at runtime by name).
 * Actions: createInvoiceLink (args: invoiceId). Returns a map with url, amount, currencyCode,
 * invoiceNumber and expiresAt, the same fields as PMS_StripeCheckout.Result.
 */
@NamespaceAccessible
public with sharing class PMS_StripePayLinkProvider implements System.Callable {
  @NamespaceAccessible
  public PMS_StripePayLinkProvider() {
  }

  @NamespaceAccessible
  public Object call(String action, Map<String, Object> args) {
    if (action == 'createInvoiceLink') {
      PMS_StripeCheckout.Result r = PMS_StripeCheckout.createForInvoice(
        (Id) args?.get('invoiceId')
      );
      return new Map<String, Object>{
        'url' => r.url,
        'amount' => r.amount,
        'currencyCode' => r.currencyCode,
        'invoiceNumber' => r.invoiceNumber,
        'expiresAt' => r.expiresAt
      };
    }
    throw new IllegalArgumentException('Unknown action: ' + action);
  }
}
