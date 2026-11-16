/**
 * Rent change notices for PMS_RentIndexService, in the PMS email style (HTML plus plain text,
 * from the org-wide address whose display name starts with "PMS", when there is one).
 */
public without sharing class PMS_RentNotices {
  private static Boolean oweaLoaded = false;
  private static Id cachedOwea;

  public static Messaging.SingleEmailMessage notice(
    PMS_Rent_Adjustment__c a,
    List<String> to
  ) {
    String first = a.Lease__r.Primary_Contact__r == null
      ? null
      : a.Lease__r.Primary_Contact__r.FirstName;
    String greeting =
      'Hello' +
      (String.isBlank(first) ? '' : ' ' + first) +
      ',';
    String premises =
      (a.Lease__r.Site__r == null ? '' : a.Lease__r.Site__r.Name) +
      (a.Lease__r.Space__r == null ? '' : ', ' + a.Lease__r.Space__r.Name);
    List<String[]> rows = new List<String[]>{
      new List<String>{ 'Lease', a.Lease__r.Name },
      new List<String>{ 'Premises', premises.removeStart(', ') },
      new List<String>{ 'Rent until now', money(a.Old_Rent__c) + ' per month' },
      new List<String>{
        'New rent',
        money(a.New_Rent__c) +
        ' per month (' +
        money(a.New_Rent__c * 12) +
        ' per year)'
      },
      new List<String>{ 'Applies from', a.Effective_Date__c.format() }
    };
    String subject;
    String intro;
    if (a.Kind__c == 'Index') {
      subject =
        'Rent indexation from ' +
        a.Effective_Date__c.format() +
        ' (' +
        a.Lease__r.Name +
        ')';
      intro =
        'Under the index clause in your lease, the rent is adjusted to the consumer price index (KPI) each year. ' +
        'The calculation is shown below.';
      Decimal share = a.Lease__r.Index_Share__c == null
        ? 100
        : a.Lease__r.Index_Share__c;
      rows.add(
        new List<String>{ 'Base rent', money(a.Base_Rent__c) + ' per month' }
      );
      rows.add(
        new List<String>{
          'Base index',
          a.Base_Index__c == null ? null : a.Base_Index__c.format()
        }
      );
      rows.add(
        new List<String>{
          'Index used',
          a.Current_Index__c == null
            ? null
            : a.Current_Index__c.format() + ' (' + a.Index_Period__c + ')'
        }
      );
      rows.add(new List<String>{ 'Indexed share', share.setScale(0) + '%' });
    } else if (a.Kind__c == 'Negotiated') {
      subject =
        'New rent from ' +
        a.Effective_Date__c.format() +
        ' (' +
        a.Lease__r.Name +
        ')';
      intro =
        'Following this year\'s rent negotiation, your rent changes by ' +
        (a.Negotiated_Percent__c == null
          ? ''
          : a.Negotiated_Percent__c.setScale(2).format() + '% ') +
        'from the date below.';
    } else {
      subject =
        'Rent change from ' +
        a.Effective_Date__c.format() +
        ' (' +
        a.Lease__r.Name +
        ')';
      intro = 'As agreed, your rent changes from the date below.';
    }
    String note = a.Note__c;
    String sender = a.Lease__r.Site__r == null ? null : a.Lease__r.Site__r.Name;

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
        r[1].escapeHtml4() +
        '</strong></td></tr>';
    }
    html += '</table>';
    if (String.isNotBlank(note)) {
      text.add('');
      text.add(note);
      html += '<p>' + note.escapeHtml4().replace('\n', '<br>') + '</p>';
    }
    String closing = 'If you have questions about the new rent, reply to this email or contact us.';
    text.add('');
    text.add(closing);
    html += '<p>' + closing.escapeHtml4() + '</p>';
    if (String.isNotBlank(sender)) {
      text.add('');
      text.add(sender);
      html += '<p>' + sender.escapeHtml4() + '</p>';
    }
    html += '</div>';
    Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
    m.setToAddresses(to);
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

  private static String money(Decimal amount) {
    return amount == null ? null : amount.setScale(2).format() + ' SEK';
  }

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
}
