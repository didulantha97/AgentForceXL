/**
 * Small Metadata API (SOAP) client used by Access Setup to change an object's internal sharing default
 * and to add the PMS Access Rule sharing reason.
 *
 * Calls go through the named credential PMS_Self_Metadata (this org, OAuth as an admin), which must
 * have "Allow Formulas in HTTP Body" ticked so {!$Credential.OAuthToken} becomes the session id.
 *
 * Changing a sharing default reads the object's current definition first and sends back only its
 * object-level settings with sharingModel replaced, so reports, history, search and the other
 * object settings are kept. Fields, list views and other child components are left out of the
 * update and stay as they are.
 */
public with sharing class PMS_AccessMetadataClient {
  public static final String NAMED_CREDENTIAL = 'PMS_Self_Metadata';
  public static final String API_VERSION = '62.0';
  public static final String SHARING_REASON = 'PMS_Access_Rule__c';
  public static final String SHARING_REASON_LABEL = 'PMS Access Rule';

  static final String MD = 'http://soap.sforce.com/2006/04/metadata';
  static final String SOAP_NS = 'http://schemas.xmlsoap.org/soap/envelope/';
  static final String XSI = 'http://www.w3.org/2001/XMLSchema-instance';

  /** Child components of a CustomObject: never sent back in an update. */
  @TestVisible
  static final Set<String> CHILD_ELEMENTS = new Set<String>{
    'fields',
    'listViews',
    'recordTypes',
    'validationRules',
    'webLinks',
    'compactLayouts',
    'businessProcesses',
    'fieldSets',
    'sharingReasons',
    'sharingRecalculations',
    'indexes'
  };

  public class MetadataException extends Exception {
  }

  /** Tests answer the calls here instead of over HTTP, so several passes can run in one test. */
  @TestVisible
  static HttpCalloutMock transport;

  public class Result {
    public String fullName;
    public Boolean success = false;
    public String message;
  }

  // ------------------------------------------------------------------ public

  /** A cheap call that proves the connection works. Throws a readable error when it doesn't. */
  public static void ping() {
    call(
      '<met:readMetadata><met:type>SharingReason</met:type><met:fullNames>PMS_Site__c.' +
        SHARING_REASON +
        '</met:fullNames></met:readMetadata>'
    );
  }

  /** Sets the internal sharing default (Private, Read or ReadWrite) of up to 10 objects per call. */
  public static List<Result> setSharingModels(
    Map<String, String> modelByObject
  ) {
    List<Result> out = new List<Result>();
    List<String> names = new List<String>(modelByObject.keySet());
    for (List<String> chunk : chunks(names, 10)) {
      Map<String, Dom.XmlNode> current = readObjects(chunk);
      String items = '';
      for (String name : chunk) {
        Dom.XmlNode rec = current.get(name);
        if (rec == null) {
          Result r = new Result();
          r.fullName = name;
          r.message = 'Salesforce did not return the object definition.';
          out.add(r);
          continue;
        }
        items +=
          '<met:metadata xsi:type="met:CustomObject">' +
          objectSettings(rec, modelByObject.get(name)) +
          '</met:metadata>';
      }
      if (String.isNotBlank(items)) {
        out.addAll(
          saveResults(
            call('<met:updateMetadata>' + items + '</met:updateMetadata>'),
            'updateMetadataResponse'
          )
        );
      }
    }
    return out;
  }

  /** Adds the PMS Access Rule sharing reason to these objects. An existing reason counts as success. */
  public static List<Result> createSharingReasons(List<String> objects) {
    List<Result> out = new List<Result>();
    for (List<String> chunk : chunks(objects, 10)) {
      String items = '';
      for (String o : chunk) {
        items +=
          '<met:metadata xsi:type="met:SharingReason"><met:fullName>' +
          o.escapeXml() +
          '.' +
          SHARING_REASON +
          '</met:fullName><met:label>' +
          SHARING_REASON_LABEL +
          '</met:label></met:metadata>';
      }
      for (
        Result r : saveResults(
          call('<met:createMetadata>' + items + '</met:createMetadata>'),
          'createMetadataResponse'
        )
      ) {
        if (
          !r.success &&
          r.message != null &&
          r.message.containsIgnoreCase('duplicate')
        ) {
          r.success = true;
          r.message = null;
        }
        if (r.fullName != null && r.fullName.contains('.')) {
          r.fullName = r.fullName.substringBefore('.');
        }
        out.add(r);
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ internals

  static Map<String, Dom.XmlNode> readObjects(List<String> names) {
    String full = '';
    for (String n : names) {
      full += '<met:fullNames>' + n.escapeXml() + '</met:fullNames>';
    }
    Dom.XmlNode body = call(
      '<met:readMetadata><met:type>CustomObject</met:type>' +
        full +
        '</met:readMetadata>'
    );
    Map<String, Dom.XmlNode> out = new Map<String, Dom.XmlNode>();
    Dom.XmlNode resp = childNamed(body, 'readMetadataResponse');
    Dom.XmlNode result = childNamed(resp, 'result');
    if (result == null) {
      return out;
    }
    for (Dom.XmlNode rec : result.getChildElements()) {
      if (rec.getName() == 'records') {
        Dom.XmlNode fn = childNamed(rec, 'fullName');
        if (fn != null) {
          out.put(fn.getText(), rec);
        }
      }
    }
    return out;
  }

  /** The object's own settings as SOAP elements, with sharingModel replaced and child components left out. */
  @TestVisible
  static String objectSettings(Dom.XmlNode rec, String sharingModel) {
    String xml = '';
    Boolean seenSharing = false;
    for (Dom.XmlNode child : rec.getChildElements()) {
      String name = child.getName();
      if (CHILD_ELEMENTS.contains(name)) {
        continue;
      }
      if (name == 'sharingModel') {
        xml += '<met:sharingModel>' + sharingModel + '</met:sharingModel>';
        seenSharing = true;
        continue;
      }
      xml += serialize(child);
    }
    if (!seenSharing) {
      xml += '<met:sharingModel>' + sharingModel + '</met:sharingModel>';
    }
    return xml;
  }

  static String serialize(Dom.XmlNode node) {
    List<Dom.XmlNode> kids = node.getChildElements();
    String innerXml;
    if (kids.isEmpty()) {
      String t = node.getText();
      innerXml = t == null ? '' : t.escapeXml();
    } else {
      innerXml = '';
      for (Dom.XmlNode k : kids) {
        innerXml += serialize(k);
      }
    }
    return '<met:' +
      node.getName() +
      '>' +
      innerXml +
      '</met:' +
      node.getName() +
      '>';
  }

  static List<Result> saveResults(Dom.XmlNode body, String responseName) {
    List<Result> out = new List<Result>();
    Dom.XmlNode resp = childNamed(body, responseName);
    if (resp == null) {
      return out;
    }
    for (Dom.XmlNode res : resp.getChildElements()) {
      if (res.getName() != 'result') {
        continue;
      }
      Result r = new Result();
      Dom.XmlNode fn = childNamed(res, 'fullName');
      Dom.XmlNode ok = childNamed(res, 'success');
      r.fullName = fn == null ? null : fn.getText();
      r.success = ok != null && ok.getText() == 'true';
      if (!r.success) {
        List<String> msgs = new List<String>();
        for (Dom.XmlNode e : res.getChildElements()) {
          if (e.getName() == 'errors') {
            Dom.XmlNode m = childNamed(e, 'message');
            if (m != null) {
              msgs.add(m.getText());
            }
          }
        }
        r.message = msgs.isEmpty()
          ? 'Salesforce refused the change.'
          : String.join(msgs, ' ');
      }
      out.add(r);
    }
    return out;
  }

  /** Sends one SOAP call and returns the soapenv:Body element. */
  static Dom.XmlNode call(String bodyXml) {
    String envelope =
      '<?xml version="1.0" encoding="UTF-8"?>' +
      '<soapenv:Envelope xmlns:soapenv="' +
      SOAP_NS +
      '" xmlns:xsi="' +
      XSI +
      '" xmlns:met="' +
      MD +
      '">' +
      '<soapenv:Header><met:SessionHeader><met:sessionId>{!$Credential.OAuthToken}</met:sessionId></met:SessionHeader></soapenv:Header>' +
      '<soapenv:Body>' +
      bodyXml +
      '</soapenv:Body></soapenv:Envelope>';
    HttpRequest req = new HttpRequest();
    req.setEndpoint(
      'callout:' + NAMED_CREDENTIAL + '/services/Soap/m/' + API_VERSION
    );
    req.setMethod('POST');
    req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
    req.setHeader('SOAPAction', '""');
    req.setBody(envelope);
    req.setTimeout(120000);
    HttpResponse res;
    try {
      res = transport != null ? transport.respond(req) : new Http().send(req);
    } catch (Exception e) {
      throw new MetadataException(connectionHint(e.getMessage()));
    }
    Dom.Document doc = new Dom.Document();
    try {
      doc.load(res.getBody());
    } catch (Exception e) {
      throw new MetadataException(
        connectionHint(
          'HTTP ' +
            res.getStatusCode() +
            ': ' +
            String.valueOf(res.getBody()).left(200)
        )
      );
    }
    Dom.XmlNode body = doc.getRootElement().getChildElement('Body', SOAP_NS);
    if (body == null) {
      throw new MetadataException(
        connectionHint('Unexpected reply (HTTP ' + res.getStatusCode() + ').')
      );
    }
    Dom.XmlNode fault = childNamed(body, 'Fault');
    if (fault != null) {
      Dom.XmlNode fs = childNamed(fault, 'faultstring');
      throw new MetadataException(
        connectionHint(
          fs == null ? 'Salesforce returned an error.' : fs.getText()
        )
      );
    }
    return body;
  }

  /** Metadata SOAP responses vary between inherited and explicit namespaces. Match by local name. */
  static Dom.XmlNode childNamed(Dom.XmlNode parent, String name) {
    if (parent == null) {
      return null;
    }
    for (Dom.XmlNode child : parent.getChildElements()) {
      if (child.getName() == name) {
        return child;
      }
    }
    return null;
  }

  @TestVisible
  static String connectionHint(String raw) {
    String connectionGuidance = '';
    if (
      raw != null &&
      (raw.containsIgnoreCase('INVALID_SESSION_ID') ||
      raw.containsIgnoreCase('named credential') ||
      raw.containsIgnoreCase('Unauthorized endpoint') ||
      raw.containsIgnoreCase('principal'))
    ) {
      connectionGuidance = ' Check the PMS Self Metadata connection: the named credential exists, "Allow Formulas in HTTP Body" is ticked, the principal is authenticated, and your permission set has access to the principal.';
    }
    return (raw == null ? 'The Metadata API call failed.' : raw) +
      connectionGuidance;
  }

  static List<List<String>> chunks(List<String> items, Integer size) {
    List<List<String>> out = new List<List<String>>();
    List<String> cur = new List<String>();
    for (String s : items) {
      cur.add(s);
      if (cur.size() == size) {
        out.add(cur);
        cur = new List<String>();
      }
    }
    if (!cur.isEmpty()) {
      out.add(cur);
    }
    return out;
  }
}
