/**
 * Payment gateway webhook: POST /services/apexrest/pms/payments
 * Expects JSON:
 *   { "reference": "pi_123", "amount": 1000, "status": "succeeded", "type": "Payment",
 *     "method": "Card", "invoiceNumber": "INV-000001", "bookingNumber": "BKG-000001",
 *     "receivedDate": "2026-12-10" }
 * and header X-PMS-Signature = hex(HMAC-SHA256(body, PMS_Settings__c.Webhook_Secret__c)).
 * Payments are upserted on Gateway Reference, so retries never double-count.
 * Card details never reach Salesforce: the gateway's hosted page takes the card.
 */
@RestResource(urlMapping='/pms/payments')
global with sharing class PMS_PaymentWebhook {
  public class Payload {
    public String reference;
    public Decimal amount;
    public String status;
    public String type;
    public String method;
    public String invoiceNumber;
    public String bookingNumber;
    public String receivedDate;
  }

  @HttpPost
  global static void receive() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');
    String body = req.requestBody == null ? '' : req.requestBody.toString();
    if (!signatureValid(body, req.headers.get('X-PMS-Signature'))) {
      res.statusCode = 401;
      res.responseBody = Blob.valueOf('{"error":"invalid signature"}');
      return;
    }
    try {
      PMS_Payment__c p;
      // Signature verified above. While the licence is suspended, confirmed money is still recorded.
      PMS_Entitlements.beginInbound();
      try {
        p = process((Payload) JSON.deserialize(body, Payload.class));
      } finally {
        PMS_Entitlements.endInbound();
      }
      res.statusCode = 200;
      res.responseBody = Blob.valueOf(
        JSON.serialize(
          new Map<String, Object>{ 'id' => p.Id, 'status' => p.Status__c }
        )
      );
    } catch (Exception e) {
      res.statusCode = 400;
      res.responseBody = Blob.valueOf(
        JSON.serialize(new Map<String, String>{ 'error' => e.getMessage() })
      );
    }
  }

  @TestVisible
  private static Boolean signatureValid(String body, String signature) {
    PMS_Settings__c settings = PMS_Settings__c.getOrgDefaults();
    String secret = settings == null ? null : settings.Webhook_Secret__c;
    if (String.isBlank(secret) || String.isBlank(signature)) {
      return false;
    }
    String expected = EncodingUtil.convertToHex(
      Crypto.generateMac('hmacSHA256', Blob.valueOf(body), Blob.valueOf(secret))
    );
    return expected.equalsIgnoreCase(signature.trim());
  }

  public static PMS_Payment__c process(Payload p) {
    if (p == null || String.isBlank(p.reference) || p.amount == null) {
      throw new PMS_Exception('reference and amount are required');
    }
    PMS_Invoice__c inv;
    if (String.isNotBlank(p.invoiceNumber)) {
      List<PMS_Invoice__c> invs = [
        SELECT Id, Account__c, Booking__c
        FROM PMS_Invoice__c
        WHERE Name = :p.invoiceNumber
        LIMIT 1
      ];
      inv = invs.isEmpty() ? null : invs[0];
    }
    PMS_Booking__c bkg;
    if (String.isNotBlank(p.bookingNumber)) {
      List<PMS_Booking__c> bks = [
        SELECT Id, Account__c
        FROM PMS_Booking__c
        WHERE Name = :p.bookingNumber
        LIMIT 1
      ];
      bkg = bks.isEmpty() ? null : bks[0];
    }
    if (inv == null && bkg == null) {
      throw new PMS_Exception('No invoice or booking matches this payment');
    }
    Id accountId = inv != null &&
      inv.Account__c != null
      ? inv.Account__c
      : bkg?.Account__c;
    if (accountId == null) {
      throw new PMS_Exception(
        'The invoice or booking has no account to credit'
      );
    }
    PMS_Payment__c pay = new PMS_Payment__c(
      Gateway_Reference__c = p.reference,
      Amount__c = p.amount,
      Account__c = accountId,
      Invoice__c = inv == null ? null : inv.Id,
      Booking__c = bkg != null ? bkg.Id : inv?.Booking__c,
      Payment_Type__c = String.isBlank(p.type) ? 'Payment' : p.type,
      Method__c = String.isBlank(p.method) ? 'Card' : p.method,
      Received_Date__c = String.isBlank(p.receivedDate)
        ? Date.today()
        : Date.valueOf(p.receivedDate),
      Status__c = mapStatus(p.status)
    );
    upsert pay Gateway_Reference__c;
    return pay;
  }

  @TestVisible
  private static String mapStatus(String gatewayStatus) {
    String s = gatewayStatus == null ? '' : gatewayStatus.toLowerCase();
    if (
      s == 'succeeded' ||
      s == 'paid' ||
      s == 'captured' ||
      s == 'authorised' ||
      s == 'completed'
    ) {
      return 'Succeeded';
    }
    if (
      s == 'failed' ||
      s == 'canceled' ||
      s == 'cancelled' ||
      s == 'refused'
    ) {
      return 'Failed';
    }
    if (s == 'refunded') {
      return 'Refunded';
    }
    return 'Pending';
  }
}
