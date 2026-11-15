/**
 * Emails to guests and enquirers from the public booking site (/book).
 *
 *  bookingConfirmed       - sent when a website booking has been paid and becomes Confirmed.
 *                           Called from PMS_WebBookingHold.confirmPaid, which sets Confirmation_Sent__c
 *                           in the same update, so each booking is emailed once (webhook or cleanup job).
 *  viewingRequestsReceived - acknowledgement for a viewing request on a home to rent
 *                           (the Case PMS_PublicBookingController.submitEnquiry creates), from PMS_CaseTrigger.
 *
 * Salesforce only delivers emails when the transaction commits, so a rolled-back payment sends nothing.
 * A failure to send is logged and never blocks the payment or the request.
 *
 * From address: the org-wide email address whose display name starts with "PMS", when there is one
 * (recommended: Setup > Organization-Wide Addresses, e.g. "PMS Bookings" <bookings@...>, verified and
 * allowed for all profiles). Otherwise the running user's address is used, with the site name as sender name.
 *
 * Runs without sharing: the booking site guest user and the Stripe webhook have no record access.
 */
public without sharing class PMS_GuestNotifications {
  @TestVisible
  private static List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();
  private static final String FALLBACK_TZ = 'Europe/Stockholm';

  // ------------------------------------------------------------------ booking confirmation

  public static void bookingConfirmed(Set<Id> bookingIds) {
    if (bookingIds == null || bookingIds.isEmpty()) {
      return;
    }
    try {
      List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
      for (PMS_Booking__c b : [
        SELECT
          Id,
          Name,
          Start__c,
          End__c,
          Adults__c,
          Children__c,
          Amount_Paid__c,
          Total_Amount__c,
          Appointment_Mode__c,
          Primary_Contact__r.FirstName,
          Primary_Contact__r.Email,
          Room_Type_Requested__r.Name,
          Space__r.Name,
          Service__r.Name,
          Practitioner__r.Name,
          Site__r.Name,
          Site__r.Module__c,
          Site__r.Street__c,
          Site__r.Postal_Code__c,
          Site__r.City__c,
          Site__r.Phone__c,
          Site__r.Time_Zone__c,
          Site__r.Check_In_Time__c,
          Site__r.Check_Out_Time__c,
          Site__r.Currency_Code__c
        FROM PMS_Booking__c
        WHERE Id IN :bookingIds AND Primary_Contact__r.Email != NULL
      ]) {
        mails.add(confirmationEmail(b));
      }
      send(mails);
    } catch (Exception e) {
      log('booking confirmation', e);
    }
  }

  @TestVisible
  private static Messaging.SingleEmailMessage confirmationEmail(
    PMS_Booking__c b
  ) {
    String zone = String.isBlank(b.Site__r.Time_Zone__c)
      ? FALLBACK_TZ
      : b.Site__r.Time_Zone__c;
    String siteName = b.Site__r.Name;
    Boolean hotel = b.Site__r.Module__c == 'Hotel';
    List<String[]> rows = new List<String[]>();
    rows.add(new List<String>{ 'Booking reference', b.Name });
    String subject;
    if (hotel) {
      subject = 'Your stay at ' + siteName + ' is confirmed (' + b.Name + ')';
      rows.add(new List<String>{ 'Hotel', siteName });
      String room = b.Room_Type_Requested__r?.Name;
      if (String.isNotBlank(room)) {
        rows.add(new List<String>{ 'Room', room });
      }
      rows.add(
        new List<String>{
          'Arrival',
          day(b.Start__c, zone) +
          timeNote(', check-in from ', b.Site__r.Check_In_Time__c)
        }
      );
      rows.add(
        new List<String>{
          'Departure',
          day(b.End__c, zone) +
          timeNote(', check-out by ', b.Site__r.Check_Out_Time__c)
        }
      );
      if (b.Start__c != null && b.End__c != null) {
        Integer nights = PMS_DateUtil.toLocalDate(b.Start__c, zone)
          .daysBetween(PMS_DateUtil.toLocalDate(b.End__c, zone));
        rows.add(new List<String>{ 'Nights', String.valueOf(nights) });
      }
      rows.add(new List<String>{ 'Guests', guests(b) });
    } else {
      String what = b.Service__r?.Name == null
        ? 'Your appointment'
        : b.Service__r.Name;
      subject =
        'Your appointment at ' +
        siteName +
        ' is confirmed (' +
        b.Name +
        ')';
      rows.add(new List<String>{ 'Treatment', what });
      if (b.Practitioner__r != null) {
        rows.add(new List<String>{ 'With', b.Practitioner__r.Name });
      }
      if (b.Start__c != null) {
        String appointmentTime = b.Start__c.format(
          'EEEE d MMMM yyyy, HH:mm',
          zone
        );
        if (b.End__c != null) {
          appointmentTime += '-' + b.End__c.format('HH:mm', zone);
        }
        rows.add(new List<String>{ 'When', appointmentTime });
      }
      rows.add(
        new List<String>{
          'Where',
          b.Appointment_Mode__c == 'Video'
            ? 'Video call (we will send you the link)'
            : siteName
        }
      );
    }
    Decimal paid = b.Amount_Paid__c != null &&
      b.Amount_Paid__c > 0
      ? b.Amount_Paid__c
      : b.Total_Amount__c;
    if (paid != null) {
      rows.add(
        new List<String>{ 'Paid', money(paid, b.Site__r.Currency_Code__c) }
      );
    }
    String addr = address(b.Site__r);
    if (String.isNotBlank(addr)) {
      rows.add(new List<String>{ 'Address', addr });
    }
    String greeting =
      'Hello' +
      (String.isBlank(b.Primary_Contact__r.FirstName)
        ? ''
        : ' ' + b.Primary_Contact__r.FirstName) +
      ',';
    String intro = 'Thank you. We have received your payment and your booking is confirmed. A receipt from our payment provider, Stripe, is sent separately.';
    String outro =
      'If you need to change or cancel, reply to this email or call us' +
      (String.isBlank(b.Site__r.Phone__c) ? '' : ' on ' + b.Site__r.Phone__c) +
      ', quoting ' +
      b.Name +
      '.' +
      (hotel
        ? ' We look forward to welcoming you.'
        : ' We look forward to seeing you.');
    return compose(
      b.Primary_Contact__r.Email,
      subject,
      siteName,
      greeting,
      intro,
      rows,
      outro
    );
  }

  // ------------------------------------------------------------------ viewing-request acknowledgement

  /** Called from PMS_CaseTrigger (after insert). Only viewing requests from the booking site qualify. */
  public static void viewingRequestsReceived(List<Case> cases) {
    try {
      List<Case> requests = new List<Case>();
      Set<Id> spaceIds = new Set<Id>();
      for (Case c : cases) {
        if (isViewingRequest(c)) {
          requests.add(c);
          spaceIds.add(c.PMS_Space__c);
        }
      }
      if (requests.isEmpty()) {
        return;
      }
      Map<Id, PMS_Space__c> units = new Map<Id, PMS_Space__c>(
        [
          SELECT
            Id,
            Name,
            Site__r.Name,
            Site__r.Phone__c,
            Site__r.Street__c,
            Site__r.Postal_Code__c,
            Site__r.City__c
          FROM PMS_Space__c
          WHERE Id IN :spaceIds
        ]
      );
      List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
      for (Case c : requests) {
        PMS_Space__c u = units.get(c.PMS_Space__c);
        if (u == null) {
          continue;
        }
        String siteName = u.Site__r?.Name;
        String firstName = String.isBlank(c.SuppliedName)
          ? ''
          : c.SuppliedName.normalizeSpace().substringBefore(' ');
        List<String[]> rows = new List<String[]>{
          new List<String>{ 'Reference', c.CaseNumber },
          new List<String>{
            'Home',
            u.Name + (siteName == null ? '' : ', ' + siteName)
          }
        };
        String addr = u.Site__r == null ? null : address(u.Site__r);
        if (String.isNotBlank(addr)) {
          rows.add(new List<String>{ 'Address', addr });
        }
        if (String.isNotBlank(c.Description)) {
          rows.add(
            new List<String>{ 'Your message', c.Description.abbreviate(500) }
          );
        }
        String phone = u.Site__r?.Phone__c;
        mails.add(
          compose(
            c.SuppliedEmail,
            'We have received your viewing request (' + c.CaseNumber + ')',
            siteName,
            'Hello' + (String.isBlank(firstName) ? '' : ' ' + firstName) + ',',
            'Thank you for your interest. We have received your request to view this home, and one of our team will contact you within one working day to arrange a time.',
            rows,
            'If anything changes, reply to this email' +
              (String.isBlank(phone) ? '' : ' or call us on ' + phone) +
              ', quoting ' +
              c.CaseNumber +
              '.'
          )
        );
      }
      send(mails);
    } catch (Exception e) {
      log('viewing request acknowledgement', e);
    }
  }

  @TestVisible
  private static Boolean isViewingRequest(Case c) {
    return c.Origin == 'Web' &&
      String.isNotBlank(c.SuppliedEmail) &&
      c.PMS_Module__c == 'Property' &&
      c.PMS_Space__c != null &&
      c.Subject != null &&
      c.Subject.startsWith('Viewing request');
  }

  // ------------------------------------------------------------------ composing and sending

  private static Messaging.SingleEmailMessage compose(
    String toAddress,
    String subject,
    String senderName,
    String greeting,
    String intro,
    List<String[]> rows,
    String outro
  ) {
    List<String> text = new List<String>{ greeting, '', intro, '' };
    String html =
      '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.5;max-width:560px">' +
      '<p>' +
      esc(greeting) +
      '</p><p>' +
      esc(intro) +
      '</p>' +
      '<table cellpadding="6" cellspacing="0" style="border-collapse:collapse;margin:12px 0;width:100%">';
    for (String[] r : rows) {
      if (String.isBlank(r[1])) {
        continue;
      }
      text.add(r[0] + ': ' + r[1]);
      html +=
        '<tr><td style="color:#666;border-bottom:1px solid #eee;white-space:nowrap;vertical-align:top">' +
        esc(r[0]) +
        '</td><td style="border-bottom:1px solid #eee"><strong>' +
        esc(r[1]).replace('\n', '<br>') +
        '</strong></td></tr>';
    }
    html +=
      '</table><p>' +
      esc(outro) +
      '</p>' +
      (String.isBlank(senderName)
        ? ''
        : '<p>Kind regards,<br>' + esc(senderName) + '</p>') +
      '</div>';
    text.add('');
    text.add(outro);
    if (String.isNotBlank(senderName)) {
      text.add('');
      text.add('Kind regards,');
      text.add(senderName);
    }
    Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
    m.setToAddresses(new List<String>{ toAddress });
    m.setSubject(subject.left(255));
    m.setPlainTextBody(String.join(text, '\n'));
    m.setHtmlBody(html);
    m.setSaveAsActivity(false);
    m.setCharset('UTF-8');
    Id owea = fromAddressId();
    if (owea != null) {
      m.setOrgWideEmailAddressId(owea);
    } else if (String.isNotBlank(senderName)) {
      m.setSenderDisplayName(senderName.left(100));
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
        for (Messaging.SendEmailError err : r.getErrors()) {
          System.debug(
            LoggingLevel.ERROR,
            'PMS guest email not sent: ' +
              err.getStatusCode() +
              ' ' +
              err.getMessage()
          );
        }
      }
    }
  }

  private static Boolean oweaLoaded = false;
  private static Id oweaId;

  private static Id fromAddressId() {
    if (!oweaLoaded) {
      oweaLoaded = true;
      try {
        List<OrgWideEmailAddress> found = [
          SELECT Id
          FROM OrgWideEmailAddress
          WHERE DisplayName LIKE 'PMS%'
          ORDER BY DisplayName
          LIMIT 1
        ];
        oweaId = found.isEmpty() ? null : found[0].Id;
      } catch (Exception e) {
        oweaId = null;
      }
    }
    return oweaId;
  }

  // ------------------------------------------------------------------ formatting

  private static String day(Datetime dt, String zone) {
    return dt == null ? '' : dt.format('EEEE d MMMM yyyy', zone);
  }

  private static String timeNote(String prefix, Time t) {
    return t == null ? '' : prefix + String.valueOf(t).left(5);
  }

  private static String guests(PMS_Booking__c b) {
    Integer a = b.Adults__c == null ? 1 : b.Adults__c.intValue();
    Integer c = b.Children__c == null ? 0 : b.Children__c.intValue();
    String s = a + (a == 1 ? ' adult' : ' adults');
    if (c > 0) {
      s += ', ' + c + (c == 1 ? ' child' : ' children');
    }
    return s;
  }

  @TestVisible
  private static String money(Decimal amount, String currencyCode) {
    Decimal v = amount.setScale(2);
    String whole = String.valueOf(v.abs().intValue());
    String grouped = '';
    while (whole.length() > 3) {
      grouped = ' ' + whole.right(3) + grouped;
      whole = whole.left(whole.length() - 3);
    }
    String cents = String.valueOf(v.abs()).substringAfter('.').rightPad(2, '0');
    return (v < 0 ? '-' : '') +
      whole +
      grouped +
      '.' +
      cents +
      (String.isBlank(currencyCode) ? '' : ' ' + currencyCode);
  }

  private static String address(PMS_Site__c s) {
    List<String> parts = new List<String>();
    for (
      String p : new List<String>{ s.Street__c, s.Postal_Code__c, s.City__c }
    ) {
      if (String.isNotBlank(p)) {
        parts.add(p.replace('\n', ', '));
      }
    }
    return String.join(parts, ', ');
  }

  private static String esc(String s) {
    return s == null ? '' : s.escapeHtml4();
  }

  private static void log(String what, Exception e) {
    System.debug(
      LoggingLevel.ERROR,
      'PMS ' +
        what +
        ' failed: ' +
        e.getMessage() +
        '\n' +
        e.getStackTraceString()
    );
  }
}
