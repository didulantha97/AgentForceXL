/**
 * Stripe webhook: POST /services/apexrest/pms/stripe, exposed to Stripe through the "PMS Payments" site.
 *
 * Every call is checked against the Stripe-Signature header using the endpoint's signing secret
 * (whsec_...), stored in PMS Settings > Webhook Secret. Calls older than 5 minutes are rejected.
 * Payments are upserted on Gateway Reference (the PaymentIntent id), so Stripe retries never double-count,
 * and a Succeeded payment is never downgraded by a late event.
 *
 * Handled events (anything else is acknowledged with 200 and ignored):
 *   checkout.session.completed               -> Payment (Succeeded, or Pending for delayed methods);
 *                                               setup-mode sessions (card guarantees) are skipped here
 *   checkout.session.async_payment_succeeded -> Payment Succeeded
 *   checkout.session.async_payment_failed    -> Payment Failed
 *   charge.refunded                          -> one Refund per charge holding the total refunded so far
 *   setup_intent.succeeded, payment_intent.* -> card guarantees, deposits, holds and policy fees
 *                                               (PMS_GuaranteeEvents; only intents PMS created)
 *
 * The invoice or booking comes from the Checkout metadata (invoiceNumber / bookingNumber), which
 * PMS_StripeCheckout sets. Runs without sharing because Stripe calls in as the site guest user.
 */
@RestResource(urlMapping='/pms/stripe')
global without sharing class PMS_StripeWebhook {
  @TestVisible
  private static final Integer TOLERANCE_SECONDS = 300;
  @TestVisible
  private static Long clockOverride; // seconds since epoch, for tests

  private static final Set<String> ALLOWED_TYPES = new Set<String>{
    'Payment',
    'Deposit',
    'Retainer'
  };

  @HttpPost
  global static void receive() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');
    String body = req.requestBody == null ? '' : req.requestBody.toString();
    if (!signatureValid(body, header(req, 'Stripe-Signature'))) {
      respond(
        res,
        401,
        new Map<String, Object>{ 'error' => 'invalid signature' }
      );
      return;
    }
    try {
      Map<String, Object> event = (Map<String, Object>) JSON.deserializeUntyped(
        body
      );
      PMS_Payment__c p = handle(event);
      respond(
        res,
        200,
        p == null
          ? new Map<String, Object>{ 'ignored' => event.get('type') }
          : new Map<String, Object>{ 'id' => p.Id, 'status' => p.Status__c }
      );
    } catch (Exception e) {
      respond(res, 400, new Map<String, Object>{ 'error' => e.getMessage() });
    }
  }

  // ---------------------------------------------------------------- signature

  @TestVisible
  private static Boolean signatureValid(String body, String header) {
    PMS_Settings__c settings = PMS_Settings__c.getOrgDefaults();
    String secret = settings == null ? null : settings.Webhook_Secret__c;
    if (String.isBlank(secret) || String.isBlank(header)) {
      return false;
    }
    String ts;
    List<String> signatures = new List<String>();
    for (String part : header.split(',')) {
      List<String> kv = part.trim().split('=', 2);
      if (kv.size() != 2) {
        continue;
      }
      if (kv[0] == 't') {
        ts = kv[1];
      } else if (kv[0] == 'v1') {
        signatures.add(kv[1]);
      }
    }
    if (String.isBlank(ts) || !ts.isNumeric() || signatures.isEmpty()) {
      return false;
    }
    if (Math.abs(now() - Long.valueOf(ts)) > TOLERANCE_SECONDS) {
      return false;
    }
    String expected = sign(ts + '.' + body, secret);
    for (String s : signatures) {
      if (expected.equalsIgnoreCase(s)) {
        return true;
      }
    }
    return false;
  }

  @TestVisible
  private static String sign(String payload, String secret) {
    return EncodingUtil.convertToHex(
      Crypto.generateMac(
        'hmacSHA256',
        Blob.valueOf(payload),
        Blob.valueOf(secret)
      )
    );
  }

  private static Long now() {
    return clockOverride != null
      ? clockOverride
      : Datetime.now().getTime() / 1000;
  }

  // ---------------------------------------------------------------- events

  @TestVisible
  private static PMS_Payment__c handle(Map<String, Object> event) {
    String eventType = (String) event.get('type');
    Map<String, Object> data = (Map<String, Object>) event.get('data');
    Map<String, Object> obj = data == null
      ? null
      : (Map<String, Object>) data.get('object');
    if (obj == null) {
      return null;
    }
    Date received = eventDate(event);
    switch on eventType {
      when 'checkout.session.completed',
        'checkout.session.async_payment_succeeded',
        'checkout.session.async_payment_failed' {
        if (str(obj, 'mode') == 'setup') {
          return null; // card saved without a payment: setup_intent.succeeded carries the card
        }
        String status;
        if (eventType == 'checkout.session.async_payment_failed') {
          status = 'Failed';
        } else if (str(obj, 'payment_status') == 'unpaid') {
          status = 'Pending';
        } else {
          status = 'Succeeded';
        }
        String ref = String.isNotBlank(str(obj, 'payment_intent'))
          ? str(obj, 'payment_intent')
          : str(obj, 'id');
        Decimal amount = toMajor(obj.get('amount_total'), str(obj, 'currency'));
        return recordPayment(ref, amount, status, metadata(obj), received);
      }
      when 'charge.refunded' {
        return recordRefund(obj, received);
      }
      when 'setup_intent.succeeded' {
        return PMS_GuaranteeEvents.setupSucceeded(obj);
      }
      when 'payment_intent.succeeded',
        'payment_intent.payment_failed',
        'payment_intent.amount_capturable_updated',
        'payment_intent.canceled' {
        return PMS_GuaranteeEvents.paymentIntent(eventType, obj, received);
      }
      when else {
        return null;
      }
    }
  }

  private static PMS_Payment__c recordPayment(
    String ref,
    Decimal amount,
    String status,
    Map<String, Object> md,
    Date received
  ) {
    if (String.isBlank(ref) || amount == null || amount <= 0) {
      throw new PMS_Exception(
        'The Stripe event has no payment reference or amount'
      );
    }
    List<PMS_Payment__c> existing = [
      SELECT Id, Status__c
      FROM PMS_Payment__c
      WHERE Gateway_Reference__c = :ref
      LIMIT 1
    ];
    if (
      !existing.isEmpty() &&
      existing[0].Status__c == 'Succeeded' &&
      status != 'Succeeded'
    ) {
      return existing[0]; // late or out-of-order event: never undo a confirmed payment
    }
    PMS_Invoice__c inv;
    String invoiceNumber = str(md, 'invoiceNumber');
    if (String.isNotBlank(invoiceNumber)) {
      List<PMS_Invoice__c> invs = [
        SELECT Id, Account__c, Booking__c
        FROM PMS_Invoice__c
        WHERE Name = :invoiceNumber
        LIMIT 1
      ];
      inv = invs.isEmpty() ? null : invs[0];
    }
    PMS_Booking__c bkg;
    String bookingNumber = str(md, 'bookingNumber');
    if (String.isNotBlank(bookingNumber)) {
      List<PMS_Booking__c> bks = [
        SELECT Id, Account__c
        FROM PMS_Booking__c
        WHERE Name = :bookingNumber
        LIMIT 1
      ];
      bkg = bks.isEmpty() ? null : bks[0];
    }
    if (inv == null && bkg == null) {
      throw new PMS_Exception(
        'No invoice or booking matches this payment (Checkout metadata invoiceNumber / bookingNumber)'
      );
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
    String paymentType = str(md, 'paymentType');
    PMS_Payment__c pay = new PMS_Payment__c(
      Gateway_Reference__c = ref,
      Amount__c = amount,
      Account__c = accountId,
      Invoice__c = inv == null ? null : inv.Id,
      Booking__c = bkg != null ? bkg.Id : inv?.Booking__c,
      Payment_Type__c = ALLOWED_TYPES.contains(paymentType)
        ? paymentType
        : 'Payment',
      Method__c = 'Card',
      Received_Date__c = received,
      Status__c = status
    );
    upsert pay Gateway_Reference__c;
    return pay;
  }

  private static PMS_Payment__c recordRefund(
    Map<String, Object> charge,
    Date received
  ) {
    String paymentIntent = str(charge, 'payment_intent');
    Decimal amount = toMajor(
      charge.get('amount_refunded'),
      str(charge, 'currency')
    );
    if (String.isBlank(paymentIntent) || amount == null || amount <= 0) {
      return null;
    }
    List<PMS_Payment__c> originals = [
      SELECT Account__c, Invoice__c, Booking__c
      FROM PMS_Payment__c
      WHERE Gateway_Reference__c = :paymentIntent
      LIMIT 1
    ];
    if (originals.isEmpty()) {
      throw new PMS_Exception('No PMS payment found for ' + paymentIntent);
    }
    PMS_Payment__c original = originals[0];
    PMS_Payment__c refund = new PMS_Payment__c(
      Gateway_Reference__c = 'refund:' + str(charge, 'id'),
      Amount__c = amount,
      Account__c = original.Account__c,
      Invoice__c = original.Invoice__c,
      Booking__c = original.Booking__c,
      Payment_Type__c = 'Refund',
      Method__c = 'Card',
      Received_Date__c = received,
      Status__c = 'Succeeded'
    );
    upsert refund Gateway_Reference__c;
    return refund;
  }

  // ---------------------------------------------------------------- helpers

  /** Stripe amounts are in the smallest currency unit (öre, cents); zero-decimal currencies are not divided. */
  @TestVisible
  private static Decimal toMajor(Object minor, String currencyCode) {
    if (minor == null) {
      return null;
    }
    Decimal d = Decimal.valueOf(String.valueOf(minor));
    if (
      currencyCode != null &&
      PMS_StripeCheckout.ZERO_DECIMAL.contains(currencyCode.toLowerCase())
    ) {
      return d;
    }
    return (d / 100).setScale(2);
  }

  private static Date eventDate(Map<String, Object> event) {
    Object created = event.get('created');
    if (created == null) {
      return Date.today();
    }
    return Datetime.newInstance(Long.valueOf(String.valueOf(created)) * 1000)
      .date();
  }

  private static Map<String, Object> metadata(Map<String, Object> obj) {
    Object md = obj.get('metadata');
    return md instanceof Map<String, Object>
      ? (Map<String, Object>) md
      : new Map<String, Object>();
  }

  private static String str(Map<String, Object> m, String key) {
    Object v = m == null ? null : m.get(key);
    return v == null ? null : String.valueOf(v);
  }

  private static String header(RestRequest req, String name) {
    if (req.headers == null) {
      return null;
    }
    for (String k : req.headers.keySet()) {
      if (k != null && k.equalsIgnoreCase(name)) {
        return req.headers.get(k);
      }
    }
    return null;
  }

  private static void respond(
    RestResponse res,
    Integer code,
    Map<String, Object> body
  ) {
    res.statusCode = code;
    res.responseBody = Blob.valueOf(JSON.serialize(body));
  }
}
