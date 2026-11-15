/**
 * Business rules for work orders, vendor quotes and vendor bills (triggers PMS_WorkOrderTrigger,
 * PMS_VendorQuoteTrigger, PMS_VendorBillTrigger) and the emails between staff and vendors.
 *
 *  Work order from a Case    Site, Space, Subject, Description and Entry Permission are copied when blank.
 *  Vendor assigned           status New becomes Assigned; the vendor's portal users are emailed
 *                            (also when staff move it to Quote Requested).
 *  Quote Accepted            the work order becomes Approved with Not to Exceed = quote total; other
 *                            open quotes are Rejected; the vendor is emailed. Rejected quotes are emailed too.
 *  Bill                      Site and Vendor are copied from the work order; the vendor is emailed when a
 *                            bill is Approved, Rejected or Paid.
 *  Vendor actions in the portal (quote, start, complete, bill) email the work order's owner.
 */
public without sharing class PMS_WorkOrderService {
  public static final String PORTAL_NAME = 'PMS Partner Portal';
  public static final Set<String> NOTIFY_VENDOR_STATUSES = new Set<String>{
    'Assigned',
    'Quote Requested'
  };
  @TestVisible
  private static List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();

  // ------------------------------------------------------------------ work orders

  public static void beforeWorkOrders(
    List<PMS_Work_Order__c> rows,
    Map<Id, PMS_Work_Order__c> oldMap
  ) {
    Set<Id> caseIds = new Set<Id>();
    Set<Id> siteIds = new Set<Id>();
    for (PMS_Work_Order__c w : rows) {
      if (w.Case__c != null) {
        caseIds.add(w.Case__c);
      }
      if (w.Site__c != null) {
        siteIds.add(w.Site__c);
      }
    }
    Map<Id, Case> cases = caseIds.isEmpty()
      ? new Map<Id, Case>()
      : new Map<Id, Case>(
          [
            SELECT
              Id,
              Subject,
              Description,
              PMS_Site__c,
              PMS_Space__c,
              Entry_Permission__c,
              Priority
            FROM Case
            WHERE Id IN :caseIds
          ]
        );
    for (Case c : cases.values()) {
      if (c.PMS_Site__c != null) {
        siteIds.add(c.PMS_Site__c);
      }
    }
    Map<Id, PMS_Site__c> sites = siteIds.isEmpty()
      ? new Map<Id, PMS_Site__c>()
      : new Map<Id, PMS_Site__c>(
          [SELECT Id, Currency_Code__c FROM PMS_Site__c WHERE Id IN :siteIds]
        );
    for (PMS_Work_Order__c w : rows) {
      Case c = w.Case__c == null ? null : cases.get(w.Case__c);
      if (c != null && oldMap == null) {
        if (w.Site__c == null) {
          w.Site__c = c.PMS_Site__c;
        }
        if (w.Space__c == null) {
          w.Space__c = c.PMS_Space__c;
        }
        if (String.isBlank(w.Subject__c)) {
          w.Subject__c = c.Subject == null ? null : c.Subject.left(255);
        }
        if (String.isBlank(w.Description__c)) {
          w.Description__c = c.Description;
        }
        if (c.Entry_Permission__c == true) {
          w.Entry_Permission__c = true;
        }
        if (
          w.Priority__c == null &&
          c.Priority != null &&
          new Set<String>{ 'Low', 'Medium', 'High' }.contains(c.Priority)
        ) {
          w.Priority__c = c.Priority;
        }
      }
      if (
        String.isBlank(w.Currency_Code__c) &&
        w.Site__c != null &&
        sites.containsKey(w.Site__c)
      ) {
        w.Currency_Code__c = sites.get(w.Site__c).Currency_Code__c;
      }
      if (
        w.Vendor_Account__c != null &&
        (w.Status__c == null ||
        w.Status__c == 'New')
      ) {
        w.Status__c = 'Assigned';
      }
      if (w.Status__c == 'Completed' && w.Completed_Date__c == null) {
        w.Completed_Date__c = Date.today();
      }
    }
  }

  public static void afterWorkOrders(
    List<PMS_Work_Order__c> rows,
    Map<Id, PMS_Work_Order__c> oldMap
  ) {
    List<PMS_Work_Order__c> toNotify = new List<PMS_Work_Order__c>();
    for (PMS_Work_Order__c w : rows) {
      PMS_Work_Order__c old = oldMap == null ? null : oldMap.get(w.Id);
      Boolean becameRelevant =
        old == null ||
        old.Vendor_Account__c != w.Vendor_Account__c ||
        old.Status__c != w.Status__c;
      if (
        w.Vendor_Account__c != null &&
        NOTIFY_VENDOR_STATUSES.contains(w.Status__c) &&
        becameRelevant
      ) {
        toNotify.add(w);
      }
    }
    if (toNotify.isEmpty()) {
      return;
    }
    Map<Id, PMS_Work_Order__c> full = new Map<Id, PMS_Work_Order__c>(
      [
        SELECT
          Id,
          Name,
          Subject__c,
          Status__c,
          Priority__c,
          Vendor_Account__c,
          Site__r.Name,
          Space__r.Name,
          Scheduled_Date__c
        FROM PMS_Work_Order__c
        WHERE Id IN :new Map<Id, PMS_Work_Order__c>(toNotify).keySet()
      ]
    );
    for (PMS_Work_Order__c w : full.values()) {
      Boolean quote = w.Status__c == 'Quote Requested';
      emailVendor(
        w.Vendor_Account__c,
        (quote ? 'Quote requested: ' : 'New work order: ') +
          w.Name +
          ' ' +
          nz(w.Subject__c),
        quote
          ? 'We would like a quote for the job below. Please submit your price in the partner portal.'
          : 'You have been assigned the job below. Please accept it in the partner portal.',
        new List<String[]>{
          new List<String>{ 'Work order', w.Name },
          new List<String>{ 'Job', nz(w.Subject__c) },
          new List<String>{ 'Location', location(w) },
          new List<String>{ 'Priority', nz(w.Priority__c) },
          new List<String>{
            'Scheduled',
            w.Scheduled_Date__c == null ? '' : w.Scheduled_Date__c.format()
          }
        }
      );
    }
  }

  // ------------------------------------------------------------------ quotes

  public static void afterQuotes(
    List<PMS_Vendor_Quote__c> rows,
    Map<Id, PMS_Vendor_Quote__c> oldMap
  ) {
    Map<Id, PMS_Vendor_Quote__c> accepted = new Map<Id, PMS_Vendor_Quote__c>();
    List<PMS_Vendor_Quote__c> rejected = new List<PMS_Vendor_Quote__c>();
    for (PMS_Vendor_Quote__c q : rows) {
      PMS_Vendor_Quote__c old = oldMap == null ? null : oldMap.get(q.Id);
      if (old != null && old.Status__c == q.Status__c) {
        continue;
      }
      if (q.Status__c == 'Accepted') {
        if (accepted.containsKey(q.Work_Order__c)) {
          q.addError('Only one quote per work order can be accepted.');
          continue;
        }
        accepted.put(q.Work_Order__c, q);
      } else if (q.Status__c == 'Rejected' && old != null) {
        rejected.add(q);
      }
    }
    if (!accepted.isEmpty()) {
      List<PMS_Work_Order__c> wos = new List<PMS_Work_Order__c>();
      for (PMS_Vendor_Quote__c q : accepted.values()) {
        wos.add(
          new PMS_Work_Order__c(
            Id = q.Work_Order__c,
            Status__c = 'Approved',
            Not_To_Exceed__c = nz(q.Amount__c) + nz(q.Tax_Amount__c),
            Vendor_Account__c = q.Vendor_Account__c
          )
        );
      }
      update wos;
      Set<Id> acceptedIds = new Map<Id, PMS_Vendor_Quote__c>(accepted.values())
        .keySet();
      List<PMS_Vendor_Quote__c> others = [
        SELECT Id
        FROM PMS_Vendor_Quote__c
        WHERE
          Work_Order__c IN :accepted.keySet()
          AND Status__c = 'Submitted'
          AND Id NOT IN :acceptedIds
      ];
      for (PMS_Vendor_Quote__c o : others) {
        o.Status__c = 'Rejected';
        o.Decision_Notes__c = 'Another quote was accepted.';
      }
      update others; // re-enters this trigger and emails those vendors
    }
    List<PMS_Vendor_Quote__c> decided = new List<PMS_Vendor_Quote__c>(
      accepted.values()
    );
    decided.addAll(rejected);
    if (decided.isEmpty()) {
      return;
    }
    for (PMS_Vendor_Quote__c q : [
      SELECT
        Id,
        Name,
        Status__c,
        Total__c,
        Decision_Notes__c,
        Vendor_Account__c,
        Work_Order__r.Name,
        Work_Order__r.Subject__c,
        Work_Order__r.Currency_Code__c,
        Work_Order__r.Site__r.Name,
        Work_Order__r.Space__r.Name
      FROM PMS_Vendor_Quote__c
      WHERE Id IN :new Map<Id, PMS_Vendor_Quote__c>(decided).keySet()
    ]) {
      Boolean ok = q.Status__c == 'Accepted';
      emailVendor(
        q.Vendor_Account__c,
        'Quote ' +
          (ok ? 'accepted' : 'not accepted') +
          ': ' +
          q.Work_Order__r.Name +
          ' ' +
          nz(q.Work_Order__r.Subject__c),
        ok
          ? 'Your quote has been accepted. You can start the work and report progress in the partner portal.'
          : 'Thank you for your quote. We will not go ahead with it this time.',
        new List<String[]>{
          new List<String>{ 'Work order', q.Work_Order__r.Name },
          new List<String>{ 'Job', nz(q.Work_Order__r.Subject__c) },
          new List<String>{
            'Quote',
            q.Name +
            ', ' +
            money(q.Total__c, q.Work_Order__r.Currency_Code__c)
          },
          new List<String>{ 'Notes', nz(q.Decision_Notes__c) }
        }
      );
    }
  }

  // ------------------------------------------------------------------ bills

  public static void beforeBills(List<PMS_Vendor_Bill__c> rows) {
    Set<Id> woIds = new Set<Id>();
    for (PMS_Vendor_Bill__c b : rows) {
      if (b.Work_Order__c != null) {
        woIds.add(b.Work_Order__c);
      }
    }
    if (woIds.isEmpty()) {
      return;
    }
    Map<Id, PMS_Work_Order__c> wos = new Map<Id, PMS_Work_Order__c>(
      [
        SELECT Id, Site__c, Vendor_Account__c
        FROM PMS_Work_Order__c
        WHERE Id IN :woIds
      ]
    );
    for (PMS_Vendor_Bill__c b : rows) {
      PMS_Work_Order__c w = wos.get(b.Work_Order__c);
      if (w == null) {
        continue;
      }
      if (b.Site__c == null) {
        b.Site__c = w.Site__c;
      }
      if (b.Vendor_Account__c == null) {
        b.Vendor_Account__c = w.Vendor_Account__c;
      }
    }
  }

  public static void afterBills(
    List<PMS_Vendor_Bill__c> rows,
    Map<Id, PMS_Vendor_Bill__c> oldMap
  ) {
    Set<Id> changed = new Set<Id>();
    for (PMS_Vendor_Bill__c b : rows) {
      PMS_Vendor_Bill__c old = oldMap == null ? null : oldMap.get(b.Id);
      if (
        old != null &&
        old.Status__c != b.Status__c &&
        new Set<String>{ 'Approved', 'Rejected', 'Paid' }.contains(b.Status__c)
      ) {
        changed.add(b.Id);
      }
    }
    if (changed.isEmpty()) {
      return;
    }
    for (PMS_Vendor_Bill__c b : [
      SELECT
        Id,
        Name,
        Status__c,
        Total__c,
        Paid_Date__c,
        Notes__c,
        Vendor_Invoice_Number__c,
        Vendor_Account__c,
        Work_Order__r.Name,
        Work_Order__r.Currency_Code__c,
        Site__r.Currency_Code__c
      FROM PMS_Vendor_Bill__c
      WHERE Id IN :changed
    ]) {
      String ccy = b.Work_Order__r?.Currency_Code__c != null
        ? b.Work_Order__r.Currency_Code__c
        : b.Site__r?.Currency_Code__c;
      String intro = b.Status__c == 'Paid'
        ? 'Your invoice has been paid.'
        : b.Status__c == 'Approved'
            ? 'Your invoice has been approved for payment.'
            : 'Your invoice could not be approved. Please see the notes below and contact us if anything is unclear.';
      emailVendor(
        b.Vendor_Account__c,
        'Invoice ' +
          nz(b.Vendor_Invoice_Number__c) +
          ' ' +
          b.Status__c.toLowerCase() +
          (b.Work_Order__r == null ? '' : ' (' + b.Work_Order__r.Name + ')'),
        intro,
        new List<String[]>{
          new List<String>{ 'Your invoice', nz(b.Vendor_Invoice_Number__c) },
          new List<String>{ 'Our reference', b.Name },
          new List<String>{ 'Amount', money(b.Total__c, ccy) },
          new List<String>{
            'Paid on',
            b.Paid_Date__c == null ? '' : b.Paid_Date__c.format()
          },
          new List<String>{ 'Notes', nz(b.Notes__c) }
        }
      );
    }
  }

  // ------------------------------------------------------------------ emails

  /** Tells the work order's owner (a staff user) what the vendor just did in the portal. */
  public static void emailStaff(
    Id workOrderId,
    String what,
    List<String[]> rows
  ) {
    try {
      PMS_Work_Order__c w = [
        SELECT Id, Name, Subject__c, OwnerId, Vendor_Account__r.Name
        FROM PMS_Work_Order__c
        WHERE Id = :workOrderId
      ];
      if (w.OwnerId == null || w.OwnerId.getSObjectType() != User.SObjectType) {
        return;
      }
      List<String[]> all = new List<String[]>{
        new List<String>{ 'Work order', w.Name + ' ' + nz(w.Subject__c) },
        new List<String>{
          'Vendor',
          w.Vendor_Account__r == null ? '' : w.Vendor_Account__r.Name
        }
      };
      all.addAll(rows);
      Messaging.SingleEmailMessage m = compose(
        null,
        what + ': ' + w.Name,
        what + '.',
        all,
        URL.getOrgDomainURL().toExternalForm() + '/' + w.Id
      );
      m.setTargetObjectId(w.OwnerId);
      m.setSaveAsActivity(false);
      send(new List<Messaging.SingleEmailMessage>{ m });
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS staff email failed: ' + e.getMessage()
      );
    }
  }

  public static void emailVendor(
    Id vendorAccountId,
    String subject,
    String intro,
    List<String[]> rows
  ) {
    try {
      if (vendorAccountId == null) {
        return;
      }
      List<String> to = new List<String>();
      for (User u : [
        SELECT Email
        FROM User
        WHERE
          Contact.AccountId = :vendorAccountId
          AND IsActive = TRUE
          AND ContactId != NULL
        LIMIT 20
      ]) {
        to.add(u.Email);
      }
      if (to.isEmpty()) {
        return;
      }
      send(
        new List<Messaging.SingleEmailMessage>{
          compose(to, subject, intro, rows, portalUrl())
        }
      );
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS vendor email failed: ' + e.getMessage()
      );
    }
  }

  private static Messaging.SingleEmailMessage compose(
    List<String> to,
    String subject,
    String intro,
    List<String[]> rows,
    String link
  ) {
    List<String> text = new List<String>{ 'Hello,', '', intro, '' };
    String html =
      '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.5;max-width:560px">' +
      '<p>Hello,</p><p>' +
      intro.escapeHtml4() +
      '</p><table cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%">';
    for (String[] r : rows) {
      if (String.isBlank(r[1])) {
        continue;
      }
      text.add(r[0] + ': ' + r[1]);
      html +=
        '<tr><td style="color:#666;border-bottom:1px solid #eee;white-space:nowrap;vertical-align:top">' +
        r[0].escapeHtml4() +
        '</td><td style="border-bottom:1px solid #eee"><strong>' +
        r[1].escapeHtml4() +
        '</strong></td></tr>';
    }
    html += '</table>';
    if (String.isNotBlank(link)) {
      text.add('');
      text.add('Open: ' + link);
      html +=
        '<p><a href="' +
        link.escapeHtml4() +
        '">Open in the portal</a></p>';
    }
    html += '</div>';
    Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
    if (to != null) {
      m.setToAddresses(to);
    }
    m.setSubject(subject.left(255));
    m.setPlainTextBody(String.join(text, '\n'));
    m.setHtmlBody(html);
    m.setSaveAsActivity(false);
    List<OrgWideEmailAddress> owea = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE DisplayName LIKE 'PMS%'
      ORDER BY DisplayName
      LIMIT 1
    ];
    if (!owea.isEmpty()) {
      m.setOrgWideEmailAddressId(owea[0].Id);
    }
    return m;
  }

  private static void send(List<Messaging.SingleEmailMessage> mails) {
    outbox.addAll(mails);
    for (Messaging.SendEmailResult r : Messaging.sendEmail(mails, false)) {
      if (!r.isSuccess()) {
        System.debug(
          LoggingLevel.ERROR,
          'PMS partner email not sent: ' + r.getErrors()
        );
      }
    }
  }

  private static String cachedPortalUrl;

  public static String portalUrl() {
    if (cachedPortalUrl == null) {
      try {
        List<Network> n = [
          SELECT Id
          FROM Network
          WHERE Name = :PORTAL_NAME
          LIMIT 1
        ];
        cachedPortalUrl = n.isEmpty() ? '' : Network.getLoginUrl(n[0].Id);
      } catch (Exception e) {
        cachedPortalUrl = '';
      }
      if (cachedPortalUrl == null) {
        cachedPortalUrl = '';
      }
    }
    return cachedPortalUrl;
  }

  // ------------------------------------------------------------------ helpers

  private static String location(PMS_Work_Order__c w) {
    String s = w.Space__r == null ? '' : w.Space__r.Name;
    if (w.Site__r != null) {
      s += (String.isBlank(s) ? '' : ', ') + w.Site__r.Name;
    }
    return s;
  }

  public static String money(Decimal amount, String currencyCode) {
    if (amount == null) {
      return '';
    }
    return amount.setScale(2).format() +
      (String.isBlank(currencyCode) ? '' : ' ' + currencyCode);
  }

  private static String nz(String s) {
    return s == null ? '' : s;
  }

  private static Decimal nz(Decimal d) {
    return d == null ? 0 : d;
  }
}
