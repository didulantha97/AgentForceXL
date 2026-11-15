/**
 * Creates a Stripe Checkout payment page for the open balance of an invoice.
 *
 * Stripe is called through the Stripe_API named credential, so the secret key lives in the
 * external credential and never in code or custom settings. The invoice number travels in the
 * session and PaymentIntent metadata, which is how PMS_StripeWebhook posts the payment back.
 * Checkout links expire after 24 hours; create a new one if the customer pays later.
 *
 * Used by the "Stripe Pay Link" quick action (pmsStripePayLink) and by Flow (invocable action).
 */
public with sharing class PMS_StripeCheckout {
  /** Currencies Stripe takes in whole units (no öre / cents). */
  public static final Set<String> ZERO_DECIMAL = new Set<String>{
    'bif',
    'clp',
    'djf',
    'gnf',
    'jpy',
    'kmf',
    'krw',
    'mga',
    'pyg',
    'rwf',
    'ugx',
    'vnd',
    'vuv',
    'xaf',
    'xof',
    'xpf'
  };

  public class Result {
    @AuraEnabled
    public String url;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String invoiceNumber;
    @AuraEnabled
    public Datetime expiresAt;
  }

  @AuraEnabled
  public static Result createInvoiceLink(Id invoiceId) {
    try {
      return createForInvoice(invoiceId);
    } catch (Exception e) {
      AuraHandledException ex = new AuraHandledException(e.getMessage());
      ex.setMessage(e.getMessage());
      throw ex;
    }
  }

  @InvocableMethod(
    label='PMS: Create Stripe payment link'
    description='Creates a Stripe Checkout link for the open balance of each invoice. Returns the links in the same order.'
    category='PMS'
  )
  public static List<String> createLinks(List<Id> invoiceIds) {
    List<String> urls = new List<String>();
    for (Id invoiceId : invoiceIds) {
      urls.add(createForInvoice(invoiceId).url);
    }
    return urls;
  }

  public static Result createForInvoice(Id invoiceId) {
    List<PMS_Invoice__c> invs = [
      SELECT Id, Name, Balance__c, Currency_Code__c, Status__c
      FROM PMS_Invoice__c
      WHERE Id = :invoiceId
      WITH USER_MODE
      LIMIT 1
    ];
    if (invs.isEmpty()) {
      throw new PMS_Exception('Invoice not found');
    }
    PMS_Invoice__c inv = invs[0];
    if (
      inv.Status__c == 'Void' ||
      inv.Status__c == 'Credited' ||
      inv.Status__c == 'Draft'
    ) {
      throw new PMS_Exception(
        'Invoice ' +
          inv.Name +
          ' can\'t be paid while its status is ' +
          inv.Status__c +
          '.'
      );
    }
    if (inv.Balance__c == null || inv.Balance__c <= 0) {
      throw new PMS_Exception(
        'Invoice ' + inv.Name + ' has nothing left to pay.'
      );
    }
    return createSession(inv);
  }

  private static Result createSession(PMS_Invoice__c inv) {
    String cur = (String.isBlank(inv.Currency_Code__c)
        ? UserInfo.getDefaultCurrency()
        : inv.Currency_Code__c)
      .toLowerCase();
    String returnUrl = returnUrl();
    Map<String, String> params = new Map<String, String>{
      'mode' => 'payment',
      'line_items[0][quantity]' => '1',
      'line_items[0][price_data][currency]' => cur,
      'line_items[0][price_data][unit_amount]' => String.valueOf(
        toMinor(inv.Balance__c, cur)
      ),
      'line_items[0][price_data][product_data][name]' => 'Invoice ' + inv.Name,
      'client_reference_id' => inv.Id,
      'metadata[invoiceNumber]' => inv.Name,
      'payment_intent_data[metadata][invoiceNumber]' => inv.Name,
      'success_url' => returnUrl +
      (returnUrl.contains('?') ? '&' : '?') +
      'status=paid',
      'cancel_url' => returnUrl +
      (returnUrl.contains('?') ? '&' : '?') +
      'status=cancelled'
    };
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Stripe_API/v1/checkout/sessions');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    req.setTimeout(20000);
    req.setBody(formEncode(params));
    HttpResponse res = new Http().send(req);

    Map<String, Object> body;
    try {
      body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    } catch (Exception e) {
      throw new PMS_Exception(
        'Stripe returned an unexpected response (HTTP ' +
          res.getStatusCode() +
          ').'
      );
    }
    if (res.getStatusCode() >= 300) {
      Map<String, Object> err = (Map<String, Object>) body.get('error');
      throw new PMS_Exception(
        'Stripe: ' +
        (err == null
          ? 'HTTP ' + res.getStatusCode()
          : String.valueOf(err.get('message')))
      );
    }
    Result r = new Result();
    r.url = (String) body.get('url');
    r.amount = inv.Balance__c;
    r.currencyCode = cur.toUpperCase();
    r.invoiceNumber = inv.Name;
    Object expires = body.get('expires_at');
    r.expiresAt = expires == null
      ? null
      : Datetime.newInstance(Long.valueOf(String.valueOf(expires)) * 1000);
    return r;
  }

  private static String returnUrl() {
    PMS_Settings__c s = PMS_Settings__c.getOrgDefaults();
    String url = s == null ? null : s.Checkout_Return_URL__c;
    if (String.isBlank(url)) {
      throw new PMS_Exception(
        'Set Checkout Return URL in Setup > Custom Settings > PMS Settings first.'
      );
    }
    return url;
  }

  @TestVisible
  private static Long toMinor(Decimal amount, String currencyCode) {
    Decimal d = ZERO_DECIMAL.contains(currencyCode.toLowerCase())
      ? amount
      : amount * 100;
    return d.setScale(0, RoundingMode.HALF_UP).longValue();
  }

  private static String formEncode(Map<String, String> params) {
    List<String> parts = new List<String>();
    for (String k : params.keySet()) {
      parts.add(
        EncodingUtil.urlEncode(k, 'UTF-8') +
          '=' +
          EncodingUtil.urlEncode(params.get(k), 'UTF-8')
      );
    }
    return String.join(parts, '&');
  }
}
