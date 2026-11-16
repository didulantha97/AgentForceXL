/**
 * Annual rent adjustments for leases.
 *
 * Index (commercial leases with an index clause), as in the standard Swedish clause:
 *   supplement = base rent x (index for October of the previous year - base index) / base index x indexed share
 *   new rent   = base rent + supplement, rounded to whole kronor; never below the base rent unless the
 *                lease says otherwise. Effective 1 January.
 *   Index clauses are only valid for a fixed term of at least three years (Jordabalken 12 kap. 19 §),
 *   so shorter leases get a warning and no proposal.
 * Negotiated (residential leases): the percentage agreed in the annual negotiation, from a chosen date.
 *
 * Adjustments start as Draft. Staff approve them, the notice is emailed to the tenant, and the daily
 * job (PMS_RentAdjustmentJob) applies them on the effective date: Rate Amount on the lease and the
 * active Rent charge schedules get the new monthly rent.
 */
public without sharing class PMS_RentIndexService {
  public static final String S1980 = 'KPI 1980=100';
  public static final String S2020 = 'KPI 2020=100';
  public static final Set<String> OPEN = new Set<String>{
    'Draft',
    'Approved',
    'Notice Sent'
  };

  public static final String LEASE_FIELDS =
    'Id, Name, Status__c, Lease_Type__c, Start__c, End__c, Rate_Amount__c, Rent_Frequency__c, Escalation_Percent__c, ' +
    'Index_Clause__c, Index_Series__c, Index_Base_Value__c, Index_Base_Rent__c, Index_Share__c, Index_Allow_Below_Base__c, ' +
    'Account__c, Account__r.Name, Primary_Contact__c, Primary_Contact__r.Email, Primary_Contact__r.FirstName, ' +
    'Site__c, Site__r.Name, Space__r.Name, Last_Rent_Adjustment__c';

  public class Result {
    @AuraEnabled
    public Integer created = 0;
    @AuraEnabled
    public List<String> messages = new List<String>();
  }

  // ---------------------------------------------------------------- index values

  public static Decimal indexValue(String series, Integer year, Integer month) {
    List<PMS_Index_Value__c> v = [
      SELECT Value__c
      FROM PMS_Index_Value__c
      WHERE Series__c = :series AND Year__c = :year AND Month__c = :month
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    return v.isEmpty() ? null : v[0].Value__c;
  }

  /** Whole years between start and end of the fixed term, counting a term ending the day before the anniversary as full. */
  public static Boolean termAtLeastThreeYears(PMS_Booking__c lease) {
    if (lease.Start__c == null || lease.End__c == null) {
      return false;
    }
    Date s = lease.Start__c.date();
    Date e = lease.End__c.date().addDays(1);
    return s.addYears(3) <= e;
  }

  public static Decimal indexedRent(
    Decimal baseRent,
    Decimal baseIndex,
    Decimal currentIndex,
    Decimal sharePercent,
    Boolean allowBelowBase
  ) {
    Decimal share = sharePercent == null ? 100 : sharePercent;
    Decimal supplement =
      baseRent *
      (currentIndex - baseIndex) /
      baseIndex *
      share /
      100;
    if (supplement < 0 && allowBelowBase != true) {
      supplement = 0;
    }
    return (baseRent + supplement).setScale(0, RoundingMode.HALF_UP);
  }

  // ---------------------------------------------------------------- prepare

  /** Drafts index adjustments effective 1 January of the given year, from the October index of the year before. */
  public static Result prepareIndex(Integer year, Id siteId) {
    Result r = new Result();
    Date effective = Date.newInstance(year, 1, 1);
    String q =
      'SELECT ' +
      LEASE_FIELDS +
      ' FROM PMS_Booking__c WHERE RecordType.DeveloperName = \'Lease\' ' +
      'AND Status__c IN (\'Active\', \'Confirmed\') AND Index_Clause__c = true' +
      (siteId == null ? '' : ' AND Site__c = :siteId');
    List<PMS_Booking__c> leases = Database.query(q);
    Set<Id> already = leasesWithAdjustment(leases, effective);
    Map<String, Decimal> indexBySeries = new Map<String, Decimal>();
    List<PMS_Rent_Adjustment__c> drafts = new List<PMS_Rent_Adjustment__c>();
    for (PMS_Booking__c l : leases) {
      if (already.contains(l.Id)) {
        r.messages.add(
          l.Name + ': already has an adjustment for ' + effective.format() + '.'
        );
        continue;
      }
      if (l.Lease_Type__c == 'Residential') {
        r.messages.add(
          l.Name +
          ': residential lease with an index clause. Residential rents follow the annual negotiation; use a negotiated increase.'
        );
        continue;
      }
      if (!termAtLeastThreeYears(l)) {
        r.messages.add(
          l.Name +
          ': fixed term under three years, so the index clause is not valid (JB 12:19). No proposal.'
        );
        continue;
      }
      if (l.End__c != null && l.End__c.date() < effective) {
        r.messages.add(l.Name + ': ends before ' + effective.format() + '.');
        continue;
      }
      String series = String.isBlank(l.Index_Series__c)
        ? S1980
        : l.Index_Series__c;
      if (l.Index_Base_Value__c == null || l.Index_Base_Value__c <= 0) {
        r.messages.add(l.Name + ': no base index (bastal) on the lease.');
        continue;
      }
      if (!indexBySeries.containsKey(series)) {
        indexBySeries.put(series, indexValue(series, year - 1, 10));
      }
      Decimal current = indexBySeries.get(series);
      if (current == null) {
        r.messages.add(
          l.Name +
            ': the ' +
            series +
            ' value for October ' +
            (year - 1) +
            ' is missing. Add it under Index Values.'
        );
        continue;
      }
      Decimal baseRent = l.Index_Base_Rent__c != null
        ? l.Index_Base_Rent__c
        : l.Rate_Amount__c;
      Decimal oldRent = l.Rate_Amount__c == null ? 0 : l.Rate_Amount__c;
      if (baseRent == null || baseRent <= 0) {
        r.messages.add(l.Name + ': no base rent or current rent.');
        continue;
      }
      Decimal newRent = indexedRent(
        baseRent,
        l.Index_Base_Value__c,
        current,
        l.Index_Share__c,
        l.Index_Allow_Below_Base__c
      );
      List<String> warnings = new List<String>();
      if (l.Index_Base_Rent__c == null) {
        warnings.add(
          'Base rent not set on the lease; the current rent was used.'
        );
      }
      if (l.Escalation_Percent__c != null && l.Escalation_Percent__c != 0) {
        warnings.add(
          'The lease also has an escalation %, which would raise the rent twice. Clear one.'
        );
      }
      if (l.Rent_Frequency__c != null && l.Rent_Frequency__c != 'Monthly') {
        warnings.add(
          'Rent is ' +
            l.Rent_Frequency__c +
            '; amounts are treated as the rent per period.'
        );
      }
      drafts.add(
        new PMS_Rent_Adjustment__c(
          Lease__c = l.Id,
          Kind__c = 'Index',
          Status__c = 'Draft',
          Effective_Date__c = effective,
          Old_Rent__c = oldRent,
          New_Rent__c = newRent,
          Change_Percent__c = changePercent(oldRent, newRent),
          Base_Rent__c = baseRent,
          Base_Index__c = l.Index_Base_Value__c,
          Current_Index__c = current,
          Index_Period__c = series + ', October ' + (year - 1),
          Warning__c = warnings.isEmpty()
            ? null
            : cut(String.join(warnings, ' '), 255)
        )
      );
    }
    if (!drafts.isEmpty()) {
      insert drafts;
    }
    r.created = drafts.size();
    return r;
  }

  /** Drafts a negotiated increase for the residential leases of a site (or all sites). */
  public static Result prepareNegotiated(
    Id siteId,
    Decimal percent,
    Date effective,
    String note
  ) {
    Result r = new Result();
    if (percent == null || effective == null) {
      throw new PMS_Exception(
        'Enter the agreed percentage and the date it applies from.'
      );
    }
    String q =
      'SELECT ' +
      LEASE_FIELDS +
      ' FROM PMS_Booking__c WHERE RecordType.DeveloperName = \'Lease\' ' +
      'AND Status__c IN (\'Active\', \'Confirmed\') AND Lease_Type__c = \'Residential\'' +
      (siteId == null ? '' : ' AND Site__c = :siteId');
    List<PMS_Booking__c> leases = Database.query(q);
    Set<Id> already = leasesWithAdjustment(leases, effective);
    List<PMS_Rent_Adjustment__c> drafts = new List<PMS_Rent_Adjustment__c>();
    for (PMS_Booking__c l : leases) {
      if (already.contains(l.Id)) {
        r.messages.add(
          l.Name + ': already has an adjustment for ' + effective.format() + '.'
        );
        continue;
      }
      if (l.End__c != null && l.End__c.date() < effective) {
        r.messages.add(l.Name + ': ends before ' + effective.format() + '.');
        continue;
      }
      Decimal oldRent = l.Rate_Amount__c == null ? 0 : l.Rate_Amount__c;
      if (oldRent <= 0) {
        r.messages.add(l.Name + ': no current rent.');
        continue;
      }
      Decimal newRent = (oldRent * (1 + percent / 100))
        .setScale(0, RoundingMode.HALF_UP);
      drafts.add(
        new PMS_Rent_Adjustment__c(
          Lease__c = l.Id,
          Kind__c = 'Negotiated',
          Status__c = 'Draft',
          Effective_Date__c = effective,
          Old_Rent__c = oldRent,
          New_Rent__c = newRent,
          Change_Percent__c = changePercent(oldRent, newRent),
          Negotiated_Percent__c = percent,
          Note__c = note,
          Warning__c = l.Escalation_Percent__c != null &&
            l.Escalation_Percent__c != 0
            ? 'The lease also has an escalation %, which would raise the rent twice. Clear one.'
            : null
        )
      );
    }
    if (!drafts.isEmpty()) {
      insert drafts;
    }
    r.created = drafts.size();
    return r;
  }

  private static Set<Id> leasesWithAdjustment(
    List<PMS_Booking__c> leases,
    Date effective
  ) {
    Set<Id> ids = new Map<Id, PMS_Booking__c>(leases).keySet();
    Set<Id> result = new Set<Id>();
    for (PMS_Rent_Adjustment__c a : [
      SELECT Lease__c
      FROM PMS_Rent_Adjustment__c
      WHERE
        Lease__c IN :ids
        AND Effective_Date__c = :effective
        AND Status__c != 'Cancelled'
    ]) {
      result.add(a.Lease__c);
    }
    return result;
  }

  // ---------------------------------------------------------------- approve, notify, apply

  public static Integer approve(Set<Id> adjustmentIds) {
    List<PMS_Rent_Adjustment__c> rows = [
      SELECT Id, Status__c, New_Rent__c, Old_Rent__c
      FROM PMS_Rent_Adjustment__c
      WHERE Id IN :adjustmentIds AND Status__c = 'Draft'
    ];
    for (PMS_Rent_Adjustment__c a : rows) {
      a.Status__c = 'Approved';
      a.Change_Percent__c = changePercent(a.Old_Rent__c, a.New_Rent__c);
    }
    update rows;
    return rows.size();
  }

  public static Integer cancel(Set<Id> adjustmentIds) {
    List<PMS_Rent_Adjustment__c> rows = [
      SELECT Id
      FROM PMS_Rent_Adjustment__c
      WHERE Id IN :adjustmentIds AND Status__c IN :OPEN
    ];
    for (PMS_Rent_Adjustment__c a : rows) {
      a.Status__c = 'Cancelled';
    }
    update rows;
    return rows.size();
  }

  /** Emails the notice for approved adjustments. Returns a line per adjustment. */
  public static List<String> sendNotices(Set<Id> adjustmentIds) {
    List<String> out = new List<String>();
    List<PMS_Rent_Adjustment__c> rows = [
      SELECT
        Id,
        Name,
        Kind__c,
        Status__c,
        Effective_Date__c,
        Old_Rent__c,
        New_Rent__c,
        Change_Percent__c,
        Base_Rent__c,
        Base_Index__c,
        Current_Index__c,
        Index_Period__c,
        Negotiated_Percent__c,
        Note__c,
        Lease__c,
        Lease__r.Name,
        Lease__r.Account__c,
        Lease__r.Account__r.Name,
        Lease__r.Primary_Contact__r.Email,
        Lease__r.Primary_Contact__r.FirstName,
        Lease__r.Site__r.Name,
        Lease__r.Space__r.Name,
        Lease__r.Index_Share__c
      FROM PMS_Rent_Adjustment__c
      WHERE Id IN :adjustmentIds AND Status__c IN ('Approved', 'Notice Sent')
    ];
    List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    for (PMS_Rent_Adjustment__c a : rows) {
      List<String> to = recipients(a);
      if (to.isEmpty()) {
        out.add(
          a.Lease__r.Name + ': no email address, send the notice by post.'
        );
        continue;
      }
      mails.add(PMS_RentNotices.notice(a, to));
      a.Status__c = 'Notice Sent';
      a.Notice_Sent_At__c = Datetime.now();
      a.Notice_Sent_To__c = cut(String.join(to, ', '), 255);
      out.add(
        a.Lease__r.Name + ': notice sent to ' + String.join(to, ', ') + '.'
      );
    }
    update rows;
    if (!mails.isEmpty()) {
      try {
        Messaging.sendEmail(mails, false);
      } catch (Exception e) {
        System.debug(
          LoggingLevel.WARN,
          'Rent notices not sent: ' + e.getMessage()
        );
      }
    }
    return out;
  }

  /** Applies approved or notified adjustments whose effective date has come. */
  public static Integer applyDue(Date today) {
    List<PMS_Rent_Adjustment__c> due = [
      SELECT Id, Lease__c, New_Rent__c, Effective_Date__c
      FROM PMS_Rent_Adjustment__c
      WHERE
        Status__c IN ('Approved', 'Notice Sent')
        AND Effective_Date__c <= :today
        AND New_Rent__c != NULL
      ORDER BY Effective_Date__c
      LIMIT 500
    ];
    if (due.isEmpty()) {
      return 0;
    }
    Map<Id, PMS_Rent_Adjustment__c> byLease = new Map<Id, PMS_Rent_Adjustment__c>();
    for (PMS_Rent_Adjustment__c a : due) {
      byLease.put(a.Lease__c, a); // the latest effective date wins
    }
    List<PMS_Booking__c> leases = new List<PMS_Booking__c>();
    for (PMS_Rent_Adjustment__c a : byLease.values()) {
      leases.add(
        new PMS_Booking__c(
          Id = a.Lease__c,
          Rate_Amount__c = a.New_Rent__c,
          Last_Rent_Adjustment__c = a.Effective_Date__c
        )
      );
    }
    List<PMS_Lease_Charge_Schedule__c> schedules = [
      SELECT Id, Lease__c
      FROM PMS_Lease_Charge_Schedule__c
      WHERE
        Lease__c IN :byLease.keySet()
        AND Charge_Type__c = 'Rent'
        AND Active__c = TRUE
    ];
    for (PMS_Lease_Charge_Schedule__c s : schedules) {
      s.Amount__c = byLease.get(s.Lease__c).New_Rent__c;
    }
    for (PMS_Rent_Adjustment__c a : due) {
      a.Status__c = 'Applied';
      a.Applied_At__c = Datetime.now();
    }
    update leases;
    if (!schedules.isEmpty()) {
      update schedules;
    }
    update due;
    return due.size();
  }

  // ---------------------------------------------------------------- helpers

  public static Decimal changePercent(Decimal oldRent, Decimal newRent) {
    if (oldRent == null || oldRent == 0 || newRent == null) {
      return null;
    }
    return ((newRent - oldRent) /
      oldRent *
      100)
      .setScale(2, RoundingMode.HALF_UP);
  }

  private static List<String> recipients(PMS_Rent_Adjustment__c a) {
    List<String> to = new List<String>();
    if (
      a.Lease__r.Primary_Contact__r != null &&
      String.isNotBlank(a.Lease__r.Primary_Contact__r.Email)
    ) {
      to.add(a.Lease__r.Primary_Contact__r.Email);
      return to;
    }
    if (a.Lease__r.Account__c != null) {
      for (Contact c : [
        SELECT Email
        FROM Contact
        WHERE AccountId = :a.Lease__r.Account__c AND Email != NULL
        ORDER BY CreatedDate
        LIMIT 2
      ]) {
        to.add(c.Email);
      }
    }
    return to;
  }

  public static String cut(String s, Integer max) {
    if (s == null) {
      return null;
    }
    return s.length() <= max ? s : s.left(max - 3) + '...';
  }
}
