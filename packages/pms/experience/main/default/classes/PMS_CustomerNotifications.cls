/**
 * Emails for Customer Portal v2.
 *   Document Request -> Sent        the signer (or the account's portal users) is asked to review / sign.
 *   Approval Request -> Pending     the project account's portal users are asked to decide.
 *   Check-in invitations            daily (PMS_CheckInInvitationJob): guests arriving and patients booked
 *                                   1-3 days ahead get a secure link to check in online on the booking site,
 *                                   no login needed. Each booking is invited once.
 *   Staff alerts                    emailUser() is used for check-ins, signatures and customer decisions.
 * Uses the org-wide address whose display name starts with "PMS", when there is one.
 */
public without sharing class PMS_CustomerNotifications {
  public static final String CUSTOMER_PORTAL = 'PMS Customer Portal';
  public static final String BOOKING_SITE = 'PMS Booking';
  public static final String BOOKING_SITE_PATH = '/book';
  @TestVisible
  private static List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();

  // ------------------------------------------------------------------ trigger entry points

  public static void documentsChanged(
    List<PMS_Document_Request__c> rows,
    Map<Id, PMS_Document_Request__c> oldMap
  ) {
    Set<Id> sent = new Set<Id>();
    for (PMS_Document_Request__c d : rows) {
      PMS_Document_Request__c old = oldMap == null ? null : oldMap.get(d.Id);
      if (d.Status__c == 'Sent' && (old == null || old.Status__c != 'Sent')) {
        sent.add(d.Id);
      }
    }
    if (sent.isEmpty()) {
      return;
    }
    for (PMS_Document_Request__c d : [
      SELECT
        Id,
        Name,
        Title__c,
        Message__c,
        Requires_Signature__c,
        Due_Date__c,
        Account__c,
        Contact__r.FirstName,
        Contact__r.Email
      FROM PMS_Document_Request__c
      WHERE Id IN :sent
    ]) {
      String verb = d.Requires_Signature__c ? 'review and sign' : 'read';
      List<String[]> rows2 = new List<String[]>{
        new List<String>{ 'Document', d.Title__c },
        new List<String>{ 'Reference', d.Name }
      };
      if (d.Due_Date__c != null) {
        rows2.add(
          new List<String>{ 'Please respond by', d.Due_Date__c.format() }
        );
      }
      if (String.isNotBlank(d.Message__c)) {
        rows2.add(new List<String>{ 'Message', d.Message__c });
      }
      List<String> to = d.Contact__r != null &&
        String.isNotBlank(d.Contact__r.Email)
        ? new List<String>{ d.Contact__r.Email }
        : portalEmails(d.Account__c);
      sendTo(
        to,
        (d.Requires_Signature__c ? 'Please sign: ' : 'New document: ') +
        d.Title__c,
        'Hello' +
          (d.Contact__r?.FirstName == null
            ? ''
            : ' ' + d.Contact__r.FirstName) +
          ',',
        'We have shared a document with you to ' +
          verb +
          '. Log in to your customer portal and open Documents.',
        rows2,
        loginUrl(CUSTOMER_PORTAL),
        'Open the portal'
      );
    }
  }

  public static void beforeApprovals(List<PMS_Approval_Request__c> rows) {
    Set<Id> projectIds = new Set<Id>();
    for (PMS_Approval_Request__c a : rows) {
      if (a.Account__c == null && a.Project__c != null) {
        projectIds.add(a.Project__c);
      }
    }
    if (projectIds.isEmpty()) {
      return;
    }
    Map<Id, PMS_Project__c> projects = new Map<Id, PMS_Project__c>(
      [SELECT Id, Account__c FROM PMS_Project__c WHERE Id IN :projectIds]
    );
    for (PMS_Approval_Request__c a : rows) {
      if (a.Account__c == null && projects.containsKey(a.Project__c)) {
        a.Account__c = projects.get(a.Project__c).Account__c;
      }
    }
  }

  public static void approvalsChanged(
    List<PMS_Approval_Request__c> rows,
    Map<Id, PMS_Approval_Request__c> oldMap
  ) {
    Set<Id> pending = new Set<Id>();
    for (PMS_Approval_Request__c a : rows) {
      PMS_Approval_Request__c old = oldMap == null ? null : oldMap.get(a.Id);
      if (
        a.Status__c == 'Pending' && (old == null || old.Status__c != 'Pending')
      ) {
        pending.add(a.Id);
      }
    }
    if (pending.isEmpty()) {
      return;
    }
    for (PMS_Approval_Request__c a : [
      SELECT
        Id,
        Name,
        Title__c,
        Type__c,
        Amount__c,
        Due_Date__c,
        Account__c,
        Project__r.Name
      FROM PMS_Approval_Request__c
      WHERE Id IN :pending
    ]) {
      List<String[]> r = new List<String[]>{
        new List<String>{ 'Project', a.Project__r?.Name },
        new List<String>{ 'Decision needed', a.Type__c + ': ' + a.Title__c },
        new List<String>{ 'Reference', a.Name }
      };
      if (a.Amount__c != null) {
        r.add(
          new List<String>{ 'Cost impact', a.Amount__c.setScale(2).format() }
        );
      }
      if (a.Due_Date__c != null) {
        r.add(new List<String>{ 'Please decide by', a.Due_Date__c.format() });
      }
      sendTo(
        portalEmails(a.Account__c),
        'Your approval is needed: ' + a.Title__c,
        'Hello,',
        'A decision on your project is waiting for you. Log in to your customer portal and open Projects to approve or reject it.',
        r,
        loginUrl(CUSTOMER_PORTAL),
        'Open the portal'
      );
    }
  }

  // ------------------------------------------------------------------ check-in invitations

  /** Invites guests and patients booked 1-3 days ahead to check in online. Returns the number invited. */
  public static Integer sendCheckInInvitations() {
    Datetime fromDt = Datetime.now();
    Datetime toDt = Datetime.now().addDays(3);
    List<PMS_Booking__c> candidates = [
      SELECT Id
      FROM PMS_Booking__c
      WHERE
        Status__c = 'Confirmed'
        AND Online_Check_In__c = FALSE
        AND Check_In_Invited_At__c = NULL
        AND Start__c >= :fromDt
        AND Start__c <= :toDt
        AND Primary_Contact__r.Email != NULL
        AND (Site__r.Module__c = 'Hotel'
        OR (Site__r.Module__c = 'Practice'
        AND Practitioner__c != NULL))
      LIMIT 100
    ];
    String base = siteUrl(BOOKING_SITE, BOOKING_SITE_PATH);
    List<PMS_Booking__c> stamped = new List<PMS_Booking__c>();
    List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    for (
      PMS_Booking__c b : PMS_CheckInService.loadMany(
        new Map<Id, PMS_Booking__c>(candidates).keySet()
      )
    ) {
      PMS_CheckInService.Eligible e = PMS_CheckInService.describe(b);
      if (e == null || e.done) {
        continue;
      }
      String key = String.isBlank(b.Check_In_Key__c)
        ? PMS_CheckInService.newKey()
        : b.Check_In_Key__c;
      String link = base + '?checkin=' + b.Id + '&key=' + key;
      Boolean clinic = e.kind == PMS_CheckInService.CLINIC;
      mails.add(
        compose(
          new List<String>{ b.Primary_Contact__r.Email },
          (clinic
              ? 'Before your appointment: a short health questionnaire'
              : 'Check in online for your stay') +
            ' (' +
            b.Name +
            ')',
          'Hello' +
            (b.Primary_Contact__r.Name == null
              ? ''
              : ' ' + b.Primary_Contact__r.Name.substringBefore(' ')) +
            ',',
          clinic
            ? 'Please fill in a short health questionnaire before your visit. It takes about three minutes and gives your practitioner more time for you.'
            : 'Save time at reception: check in online now, tell us when you expect to arrive, and we will have everything ready.',
          new List<String[]>{
            new List<String>{ 'Booking', e.title },
            new List<String>{ 'When', e.subtitle },
            new List<String>{ 'Reference', b.Name }
          },
          link,
          clinic ? 'Fill in the questionnaire' : 'Check in online'
        )
      );
      stamped.add(
        new PMS_Booking__c(
          Id = b.Id,
          Check_In_Key__c = key,
          Check_In_Invited_At__c = Datetime.now()
        )
      );
    }
    if (!stamped.isEmpty()) {
      update stamped;
      send(mails);
    }
    return stamped.size();
  }

  // ------------------------------------------------------------------ building blocks

  /** Plain alert to a staff user (no email limits apply to internal users). */
  public static void emailUser(
    Id userId,
    String subject,
    String text,
    Id recordId
  ) {
    try {
      if (userId == null) {
        return;
      }
      Messaging.SingleEmailMessage m = compose(
        null,
        subject,
        'Hello,',
        text,
        new List<String[]>(),
        recordId == null
          ? null
          : URL.getOrgDomainURL().toExternalForm() + '/' + recordId,
        'Open in Salesforce'
      );
      m.setTargetObjectId(userId);
      send(new List<Messaging.SingleEmailMessage>{ m });
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS staff alert failed: ' + e.getMessage()
      );
    }
  }

  public static List<String> portalEmails(Id accountId) {
    List<String> to = new List<String>();
    if (accountId == null) {
      return to;
    }
    for (User u : [
      SELECT Email
      FROM User
      WHERE
        Contact.AccountId = :accountId
        AND IsActive = TRUE
        AND ContactId != NULL
      LIMIT 20
    ]) {
      to.add(u.Email);
    }
    return to;
  }

  private static void sendTo(
    List<String> to,
    String subject,
    String greeting,
    String intro,
    List<String[]> rows,
    String link,
    String linkLabel
  ) {
    try {
      if (to == null || to.isEmpty()) {
        return;
      }
      send(
        new List<Messaging.SingleEmailMessage>{
          compose(to, subject, greeting, intro, rows, link, linkLabel)
        }
      );
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS customer email failed: ' + e.getMessage()
      );
    }
  }

  private static Messaging.SingleEmailMessage compose(
    List<String> to,
    String subject,
    String greeting,
    String intro,
    List<String[]> rows,
    String link,
    String linkLabel
  ) {
    List<String> text = new List<String>{ greeting, '', intro, '' };
    String html =
      '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.5;max-width:560px">' +
      '<p>' +
      greeting.escapeHtml4() +
      '</p><p>' +
      intro.escapeHtml4() +
      '</p>' +
      '<table cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%">';
    for (String[] r : rows) {
      if (String.isBlank(r[1])) {
        continue;
      }
      text.add(r[0] + ': ' + r[1]);
      html +=
        '<tr><td style="color:#666;border-bottom:1px solid #eee;white-space:nowrap;vertical-align:top">' +
        r[0].escapeHtml4() +
        '</td><td style="border-bottom:1px solid #eee"><strong>' +
        r[1].escapeHtml4().replace('\n', '<br>') +
        '</strong></td></tr>';
    }
    html += '</table>';
    if (String.isNotBlank(link)) {
      text.add('');
      text.add(linkLabel + ': ' + link);
      html +=
        '<p style="margin:20px 0"><a href="' +
        link.escapeHtml4() +
        '" style="background:#0b5cab;color:#fff;padding:10px 18px;' +
        'border-radius:6px;text-decoration:none;display:inline-block">' +
        linkLabel.escapeHtml4() +
        '</a></p>';
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
    Id owea = oweaId();
    if (owea != null) {
      m.setOrgWideEmailAddressId(owea);
    }
    return m;
  }

  private static void send(List<Messaging.SingleEmailMessage> mails) {
    if (mails.isEmpty()) {
      return;
    }
    outbox.addAll(mails);
    for (Messaging.SendEmailResult r : Messaging.sendEmail(mails, false)) {
      if (!r.isSuccess()) {
        System.debug(
          LoggingLevel.ERROR,
          'PMS customer email not sent: ' + r.getErrors()
        );
      }
    }
  }

  private static Boolean oweaLoaded = false;
  private static Id cachedOwea;

  private static Id oweaId() {
    if (!oweaLoaded) {
      oweaLoaded = true;
      List<OrgWideEmailAddress> o = [
        SELECT Id
        FROM OrgWideEmailAddress
        WHERE DisplayName LIKE 'PMS%'
        ORDER BY DisplayName
        LIMIT 1
      ];
      cachedOwea = o.isEmpty() ? null : o[0].Id;
    }
    return cachedOwea;
  }

  public static String loginUrl(String networkName) {
    try {
      List<Network> n = [
        SELECT Id
        FROM Network
        WHERE Name = :networkName
        LIMIT 1
      ];
      return n.isEmpty() ? null : Network.getLoginUrl(n[0].Id);
    } catch (Exception e) {
      return null;
    }
  }

  /** https://<community domain><path>, e.g. https://codeterriers4.my.site.com/book */
  public static String siteUrl(String networkName, String path) {
    String login = loginUrl(networkName);
    if (String.isNotBlank(login)) {
      String host = login.substringAfter('://').substringBefore('/');
      if (String.isNotBlank(host)) {
        return 'https://' + host + path;
      }
    }
    return URL.getOrgDomainURL()
        .toExternalForm()
        .replace('.my.salesforce.com', '.my.site.com') + path;
  }
}
