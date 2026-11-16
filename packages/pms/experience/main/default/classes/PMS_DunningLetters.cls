/**
 * Reminder letters for PMS_DunningService, in the same style as PMS_CustomerNotifications
 * (HTML plus plain text, sent from the org-wide address whose display name starts with "PMS").
 * English for now; the PMS translation catalog (multi-language phase 2) will take these texts over.
 */
public without sharing class PMS_DunningLetters {
  private static Boolean oweaLoaded = false;
  private static Id cachedOwea;

  public static Messaging.SingleEmailMessage letter(
    String step,
    PMS_Invoice__c inv,
    PMS_Dunning_Policy__c p,
    List<String> to,
    Decimal balance,
    Decimal fee,
    Decimal interest,
    Integer days,
    String link,
    PMS_DunningService.PlanBuild plan,
    Date today,
    String cur
  ) {
    String first = inv.Booking__r != null &&
      inv.Booking__r.Primary_Contact__r != null
      ? inv.Booking__r.Primary_Contact__r.FirstName
      : null;
    String greeting =
      'Hello' +
      (String.isBlank(first) ? '' : ' ' + first) +
      ',';
    String what = whatFor(inv);
    List<String[]> rows = new List<String[]>{
      new List<String>{
        'Invoice',
        inv.Name + (String.isBlank(what) ? '' : ' (' + what + ')')
      },
      new List<String>{ 'Due date', inv.Due_Date__c.format() },
      new List<String>{ 'Days overdue', String.valueOf(days) }
    };
    if (fee > 0) {
      rows.add(
        new List<String>{
          PMS_DunningService.isBusiness(inv)
            ? 'Late payment compensation'
            : 'Reminder fee',
          money(fee, cur)
        }
      );
    }
    if (interest > 0) {
      rows.add(
        new List<String>{
          'Late payment interest',
          money(interest, cur) +
          ' (' +
          PMS_DunningService.annualRate(p).setScale(2) +
          '% per year)'
        }
      );
    }
    rows.add(new List<String>{ 'Amount to pay now', money(balance, cur) });

    String subject;
    String intro;
    String linkLabel = 'Pay by card';
    if (step == PMS_DunningService.R1) {
      subject = 'Payment reminder: invoice ' + inv.Name;
      intro =
        'We have not received payment for invoice ' +
        inv.Name +
        ', which was due on ' +
        inv.Due_Date__c.format() +
        '. Please pay the amount below. If you have already paid, please ignore this reminder.';
    } else if (step == PMS_DunningService.R2) {
      Date collections = p.Collections_Days__c == null
        ? null
        : inv.Due_Date__c.addDays(p.Collections_Days__c.intValue());
      subject = 'Second reminder: invoice ' + inv.Name;
      intro =
        'Invoice ' +
        inv.Name +
        ' is still unpaid. Late payment interest is charged from the due date.' +
        (collections == null
          ? ''
          : ' If we have not received payment by ' +
            (collections > today ? collections : today.addDays(7)).format() +
            ', the claim will be passed to debt collection, which adds further costs.') +
        ' If something is wrong with the invoice, contact us straight away.';
    } else if (step == PMS_DunningService.OFFER) {
      subject = 'Pay invoice ' + inv.Name + ' in instalments';
      intro =
        'If paying the full amount at once is difficult, you can pay it in ' +
        plan.instalments.size() +
        ' monthly instalments. Paying the first instalment by ' +
        plan.instalments[0].Due_Date__c.format() +
        ' accepts the plan; you can also pay the full amount at any time.';
      for (PMS_Payment_Plan_Instalment__c i : plan.instalments) {
        rows.add(
          new List<String>{
            'Instalment ' + i.Number__c,
            money(i.Amount__c, cur) +
            ' by ' +
            i.Due_Date__c.format()
          }
        );
      }
      linkLabel = 'Pay the first instalment';
    } else {
      subject =
        'Final notice: invoice ' +
        inv.Name +
        ' goes to debt collection';
      intro =
        'Invoice ' +
        inv.Name +
        ' remains unpaid despite our reminders, so we are now passing the claim to debt collection. ' +
        'Debt collection adds further costs. Contact us straight away if you have a question about the invoice.';
    }
    String extra = p.Payment_Instructions__c;
    String sender = String.isNotBlank(p.Sender_Name__c)
      ? p.Sender_Name__c
      : (inv.Booking__r != null &&
          inv.Booking__r.Site__r != null
          ? inv.Booking__r.Site__r.Name
          : null);
    return compose(
      to,
      subject,
      greeting,
      intro,
      rows,
      link,
      linkLabel,
      extra,
      sender
    );
  }

  /** Claim details for the collections agency, when the policy has an agency email. */
  public static Messaging.SingleEmailMessage agencyEmail(
    PMS_Invoice__c inv,
    PMS_Dunning_Policy__c p,
    Decimal balance,
    Integer days,
    String cur,
    List<String> customerEmails
  ) {
    List<String[]> rows = new List<String[]>{
      new List<String>{ 'Creditor', p.Sender_Name__c },
      new List<String>{
        'Debtor',
        inv.Account__r == null ? null : inv.Account__r.Name
      },
      new List<String>{
        'Debtor type',
        PMS_DunningService.isBusiness(inv) ? 'Business' : 'Consumer'
      },
      new List<String>{ 'Debtor email', String.join(customerEmails, ', ') },
      new List<String>{ 'Invoice', inv.Name },
      new List<String>{
        'Issue date',
        inv.Issue_Date__c == null ? null : inv.Issue_Date__c.format()
      },
      new List<String>{ 'Due date', inv.Due_Date__c.format() },
      new List<String>{ 'Days overdue', String.valueOf(days) },
      new List<String>{ 'Amount claimed', money(balance, cur) },
      new List<String>{ 'Concerns', whatFor(inv) }
    };
    return compose(
      new List<String>{ p.Collections_Agency_Email__c },
      'New collections case: invoice ' + inv.Name,
      'Hello,',
      'Please take over the claim below. Reminders were sent on the dates in our records; we can send copies on request.',
      rows,
      null,
      null,
      null,
      p.Sender_Name__c
    );
  }

  private static String whatFor(PMS_Invoice__c inv) {
    if (inv.Booking__r != null) {
      String space = inv.Booking__r.Space__r == null
        ? ''
        : ', ' + inv.Booking__r.Space__r.Name;
      String site = inv.Booking__r.Site__r == null
        ? ''
        : inv.Booking__r.Site__r.Name;
      return (site + space).removeStart(', ');
    }
    return inv.Project__r == null ? null : inv.Project__r.Name;
  }

  private static String money(Decimal amount, String cur) {
    return (amount == null ? 0 : amount).setScale(2).format() + ' ' + cur;
  }

  private static Messaging.SingleEmailMessage compose(
    List<String> to,
    String subject,
    String greeting,
    String intro,
    List<String[]> rows,
    String link,
    String linkLabel,
    String extra,
    String sender
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
        r[1].escapeHtml4() +
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
    if (String.isNotBlank(extra)) {
      text.add('');
      text.add(extra);
      html +=
        '<p style="color:#444">' +
        extra.escapeHtml4().replace('\n', '<br>') +
        '</p>';
    }
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
