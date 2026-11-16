/**
 * Pay link in reminder letters: GET /services/apexrest/pms/pay?i=<invoice id>&k=<pay key>,
 * served by the PMS Payments site (the same site as the Stripe webhook).
 *
 * Checks the secret key, then opens a fresh Stripe Checkout page for what is owed now (the next
 * instalment when a payment plan is open) and redirects there. The link in the letter therefore
 * never expires, unlike Checkout pages themselves. Runs without sharing because the customer is
 * not logged in; the key is the only thing that grants access, so wrong keys get the same reply as
 * unknown invoices.
 */
@RestResource(urlMapping='/pms/pay')
global without sharing class PMS_PayLinkRest {
  @HttpGet
  global static void open() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    String invoiceId = req.params.get('i');
    String key = req.params.get('k');
    try {
      PMS_Invoice__c inv = find(invoiceId, key);
      if (inv == null) {
        page(
          res,
          404,
          'Link not valid',
          'This payment link is not valid. Please use the link in your latest reminder, or contact us.'
        );
        return;
      }
      if (
        inv.Balance__c == null ||
        inv.Balance__c <= 0 ||
        inv.Status__c == 'Paid'
      ) {
        page(
          res,
          200,
          'Already paid',
          'Invoice ' + inv.Name + ' is paid. Thank you.'
        );
        return;
      }
      Decimal amount = inv.Balance__c;
      String label = 'Invoice ' + inv.Name;
      Map<Id, PMS_Payment_Plan__c> plans = PMS_DunningService.openPlans(
        new Set<Id>{ inv.Id }
      );
      if (plans.containsKey(inv.Id)) {
        amount = PMS_DunningService.nextInstalmentAmount(
          inv,
          plans.get(inv.Id)
        );
        label = 'Instalment, invoice ' + inv.Name;
      }
      String url = checkoutUrl(inv, amount, label);
      res.statusCode = 302;
      res.addHeader('Location', url);
      res.addHeader('Cache-Control', 'no-store');
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Pay link failed: ' + e.getMessage());
      page(
        res,
        503,
        'Payment page unavailable',
        'We could not open the payment page just now. Please try again in a few minutes, or use the other payment options in your reminder.'
      );
    }
  }

  @TestVisible
  private static PMS_Invoice__c find(String invoiceId, String key) {
    if (String.isBlank(invoiceId) || String.isBlank(key) || key.length() < 16) {
      return null;
    }
    Id recordId;
    try {
      recordId = Id.valueOf(invoiceId);
    } catch (Exception e) {
      return null;
    }
    if (recordId.getSObjectType() != PMS_Invoice__c.SObjectType) {
      return null;
    }
    List<PMS_Invoice__c> invs = PMS_DunningService.load(
      new Set<Id>{ recordId }
    );
    if (
      invs.isEmpty() ||
      String.isBlank(invs[0].Pay_Key__c) ||
      !invs[0].Pay_Key__c.equals(key)
    ) {
      return null;
    }
    return invs[0];
  }

  private static String checkoutUrl(
    PMS_Invoice__c inv,
    Decimal amount,
    String label
  ) {
    String cur = PMS_DunningService.currencyOf(inv);
    PMS_Settings__c s = PMS_Settings__c.getOrgDefaults();
    String ret = s == null ? null : s.Checkout_Return_URL__c;
    if (String.isBlank(ret)) {
      throw new PMS_Exception('Checkout Return URL is not set.');
    }
    String sep = ret.contains('?') ? '&' : '?';
    Map<String, String> params = new Map<String, String>{
      'mode' => 'payment',
      'line_items[0][quantity]' => '1',
      'line_items[0][price_data][currency]' => cur.toLowerCase(),
      'line_items[0][price_data][unit_amount]' => String.valueOf(
        PMS_StripeClient.toMinor(amount, cur)
      ),
      'line_items[0][price_data][product_data][name]' => label,
      'client_reference_id' => String.valueOf(inv.Id),
      'metadata[invoiceNumber]' => inv.Name,
      'payment_intent_data[metadata][invoiceNumber]' => inv.Name,
      'success_url' => ret +
      sep +
      'status=paid',
      'cancel_url' => ret +
      sep +
      'status=cancelled',
      'expires_at' => String.valueOf(
        Datetime.now().addMinutes(60).getTime() / 1000
      )
    };
    Map<String, Object> session = PMS_StripeClient.post(
      '/v1/checkout/sessions',
      params,
      null
    );
    return PMS_StripeClient.str(session, 'url');
  }

  private static void page(
    RestResponse res,
    Integer status,
    String title,
    String message
  ) {
    res.statusCode = status;
    res.addHeader('Content-Type', 'text/html; charset=utf-8');
    res.responseBody = Blob.valueOf(
      '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
        '<title>' +
        title.escapeHtml4() +
        '</title></head>' +
        '<body style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:60px auto;padding:0 20px;color:#222">' +
        '<h1 style="font-size:22px">' +
        title.escapeHtml4() +
        '</h1><p>' +
        message.escapeHtml4() +
        '</p></body></html>'
    );
  }
}
