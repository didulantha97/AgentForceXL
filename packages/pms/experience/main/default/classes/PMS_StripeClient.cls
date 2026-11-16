/**
 * Thin client for the Stripe REST API, called through the Stripe_API named credential (the secret
 * key stays in the external credential). Used by the guarantee code (cards on file, deposits,
 * pre-authorisations and policy fees). PMS_StripeCheckout keeps its own copy of these helpers so the
 * existing pay links are untouched.
 *
 * Errors come back as StripeException with Stripe's error code and decline code, so callers can
 * tell "the bank wants the guest to authenticate" (authentication_required) from a hard failure.
 */
public without sharing class PMS_StripeClient {
  public class StripeException extends Exception {
    public String code;
    public String declineCode;
    public String paymentIntentId;
    public Integer httpStatus;
  }

  public static Map<String, Object> post(
    String path,
    Map<String, String> params,
    String idempotencyKey
  ) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Stripe_API' + path);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    if (String.isNotBlank(idempotencyKey)) {
      req.setHeader('Idempotency-Key', idempotencyKey);
    }
    req.setTimeout(20000);
    req.setBody(
      formEncode(params == null ? new Map<String, String>() : params)
    );
    return send(req);
  }

  public static Map<String, Object> get(
    String path,
    Map<String, String> query
  ) {
    String url = 'callout:Stripe_API' + path;
    if (query != null && !query.isEmpty()) {
      url += '?' + formEncode(query);
    }
    HttpRequest req = new HttpRequest();
    req.setEndpoint(url);
    req.setMethod('GET');
    req.setTimeout(20000);
    return send(req);
  }

  private static Map<String, Object> send(HttpRequest req) {
    HttpResponse res = new Http().send(req);
    Map<String, Object> body;
    try {
      body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    } catch (Exception e) {
      StripeException ex = new StripeException(
        'Stripe returned an unexpected response (HTTP ' +
          res.getStatusCode() +
          ').'
      );
      ex.httpStatus = res.getStatusCode();
      throw ex;
    }
    if (res.getStatusCode() >= 300) {
      Map<String, Object> err = asMap(body.get('error'));
      String message = err.get('message') == null
        ? 'HTTP ' + res.getStatusCode()
        : String.valueOf(err.get('message'));
      StripeException ex = new StripeException('Stripe: ' + message);
      ex.code = str(err, 'code');
      ex.declineCode = str(err, 'decline_code');
      ex.paymentIntentId = str(asMap(err.get('payment_intent')), 'id');
      ex.httpStatus = res.getStatusCode();
      throw ex;
    }
    return body;
  }

  // ---------------------------------------------------------------- helpers

  /** Currencies Stripe takes in whole units. */
  public static Boolean zeroDecimal(String currencyCode) {
    return currencyCode != null &&
      PMS_StripeCheckout.ZERO_DECIMAL.contains(currencyCode.toLowerCase());
  }

  public static Long toMinor(Decimal amount, String currencyCode) {
    Decimal d = zeroDecimal(currencyCode) ? amount : amount * 100;
    return d.setScale(0, RoundingMode.HALF_UP).longValue();
  }

  public static Decimal toMajor(Object minor, String currencyCode) {
    if (minor == null) {
      return null;
    }
    Decimal d = Decimal.valueOf(String.valueOf(minor));
    return zeroDecimal(currencyCode) ? d : (d / 100).setScale(2);
  }

  public static Map<String, Object> asMap(Object o) {
    return o instanceof Map<String, Object>
      ? (Map<String, Object>) o
      : new Map<String, Object>();
  }

  public static String str(Map<String, Object> m, String key) {
    Object v = m == null ? null : m.get(key);
    return v == null ? null : String.valueOf(v);
  }

  public static String formEncode(Map<String, String> params) {
    List<String> parts = new List<String>();
    for (String k : params.keySet()) {
      String v = params.get(k);
      if (v == null) {
        continue;
      }
      parts.add(
        EncodingUtil.urlEncode(k, 'UTF-8') +
          '=' +
          EncodingUtil.urlEncode(v, 'UTF-8')
      );
    }
    return String.join(parts, '&');
  }
}
