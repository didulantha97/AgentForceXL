/**
 * Calls the Channex API through the Channex_API named credential. The named credential holds the base
 * URL (https://staging.channex.io/api/v1, later https://secure.channex.io/api/v1) and sends the API key
 * in the user-api-key header, so the key never appears in code or settings.
 */
public without sharing class PMS_ChannexClient {
  public class ChannexException extends Exception {
    public Integer httpStatus;
  }

  public static Map<String, Object> get(String path) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Channex_API' + path);
    req.setMethod('GET');
    req.setHeader('Accept', 'application/json');
    req.setTimeout(30000);
    return send(req);
  }

  public static Map<String, Object> post(String path, Object body) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Channex_API' + path);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('Accept', 'application/json');
    req.setTimeout(60000);
    req.setBody(body == null ? '{}' : JSON.serialize(body));
    return send(req);
  }

  private static Map<String, Object> send(HttpRequest req) {
    HttpResponse res = new Http().send(req);
    String raw = res.getBody();
    Map<String, Object> body;
    try {
      body = String.isBlank(raw)
        ? new Map<String, Object>()
        : (Map<String, Object>) JSON.deserializeUntyped(raw);
    } catch (Exception e) {
      ChannexException ex = new ChannexException(
        'Channex returned an unexpected response (HTTP ' +
          res.getStatusCode() +
          ').'
      );
      ex.httpStatus = res.getStatusCode();
      throw ex;
    }
    if (res.getStatusCode() >= 300) {
      String msg = 'HTTP ' + res.getStatusCode();
      Object errors = body.get('errors');
      if (errors instanceof Map<String, Object>) {
        Map<String, Object> err = (Map<String, Object>) errors;
        msg +=
          ': ' +
          String.valueOf(err.get('title')) +
          (err.get('details') == null
            ? ''
            : ' ' + JSON.serialize(err.get('details')));
      } else if (errors != null) {
        msg += ': ' + JSON.serialize(errors);
      }
      if (res.getStatusCode() == 429) {
        msg += ' (rate limit; the next run retries)';
      }
      ChannexException ex = new ChannexException('Channex ' + msg.left(500));
      ex.httpStatus = res.getStatusCode();
      throw ex;
    }
    return body;
  }

  public static Map<String, Object> asMap(Object o) {
    return o instanceof Map<String, Object>
      ? (Map<String, Object>) o
      : new Map<String, Object>();
  }

  public static List<Object> asList(Object o) {
    return o instanceof List<Object> ? (List<Object>) o : new List<Object>();
  }

  public static String str(Map<String, Object> m, String key) {
    Object v = m == null ? null : m.get(key);
    return v == null ? null : String.valueOf(v);
  }
}
