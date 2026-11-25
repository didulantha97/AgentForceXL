/**
 * Guest data retention. Core package. Finds guests (not yet anonymised) whose last activity is older than the
 * retention period and either FLAGs them for review (default) or ANONYMISEs them.
 *
 * Last activity = latest booking End__c as primary or party guest; a guest with no booking is measured from the Contact's
 * CreatedDate. Only guests are considered: the Contact's account has role Guest, or the Contact has Guest 360 stay stats.
 * Staff, owner and vendor contacts are never touched.
 *
 * Settings (PMS_Settings__c org defaults, read dynamically so this class compiles before the fields exist):
 *   Guest_Retention_Months__c (Number, default 36 when blank or < 1)
 *   Guest_Retention_Mode__c   (Text/Picklist: FLAG default, or ANONYMISE; anything else = FLAG)
 * FLAG: sets Contact.PMS_Retention_Due__c = today (once) and nothing else.
 * ANONYMISE: PMS_GuestErasureService.anonymiseTrusted per chunk; guests blocked by the service rules (open or unpaid
 * bookings) or that fail are flagged with PMS_Retention_Due__c so a person reviews them; a failed chunk is retried one
 * guest at a time. Totals are in the debug log of finish().
 *
 * Schedule weekly from PMS_DailyJob:  Database.executeBatch(new PMS_GuestRetentionBatch(), PMS_GuestRetentionBatch.SCOPE_SIZE);
 * without sharing: must see every guest and their bookings regardless of who runs the schedule.
 */
public without sharing class PMS_GuestRetentionBatch implements Database.Batchable<SObject>, Database.Stateful {
  public static final Integer SCOPE_SIZE = 10;
  public static final Integer DEFAULT_MONTHS = 36;
  public static final String MODE_FLAG = 'FLAG';
  public static final String MODE_ANONYMISE = 'ANONYMISE';

  private Integer processed = 0;
  private Integer anonymised = 0;
  private Integer blocked = 0;
  private Integer failed = 0;
  private String firstError;

  public static Integer retentionMonths() {
    Integer m = DEFAULT_MONTHS;
    try {
      Object v = PMS_Settings__c.getOrgDefaults()
        .get('Guest_Retention_Months__c');
      if (v != null && Integer.valueOf((Decimal) v) >= 1) {
        m = Integer.valueOf((Decimal) v);
      }
    } catch (Exception e) {
      // field not present yet: default
    }
    return m;
  }

  public static String mode() {
    try {
      Object v = PMS_Settings__c.getOrgDefaults()
        .get('Guest_Retention_Mode__c');
      if (
        v != null &&
        String.valueOf(v).trim().toUpperCase() == MODE_ANONYMISE
      ) {
        return MODE_ANONYMISE;
      }
    } catch (Exception e) {
      // field not present yet: FLAG
    }
    return MODE_FLAG;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    Datetime cutoff = Datetime.now().addMonths(-retentionMonths());
    Boolean flagOnly = mode() == MODE_FLAG;
    String q =
      'SELECT Id FROM Contact WHERE PMS_Anonymised__c = false' +
      ' AND CreatedDate < :cutoff' +
      ' AND (Account.PMS_Party_Role__c INCLUDES (\'Guest\') OR PMS_Total_Stays__c > 0 OR PMS_Last_Stay__c != NULL)' +
      (flagOnly ? ' AND PMS_Retention_Due__c = NULL' : '') +
      ' AND Id NOT IN (SELECT Primary_Contact__c FROM PMS_Booking__c WHERE Primary_Contact__c != NULL AND End__c >= :cutoff)' +
      ' AND Id NOT IN (SELECT Contact__c FROM PMS_Booking_Party__c WHERE Contact__c != NULL AND Booking__r.End__c >= :cutoff)';
    return Database.getQueryLocator(q);
  }

  public void execute(Database.BatchableContext bc, List<Contact> scope) {
    processed += scope.size();
    Set<Id> ids = new Map<Id, Contact>(scope).keySet();
    if (mode() == MODE_FLAG) {
      flag(ids);
      return;
    }
    String reason =
      'Retention policy: no activity for ' +
      retentionMonths() +
      ' months';
    Map<Id, PMS_GuestErasureService.Result> res = PMS_GuestErasureService.anonymiseTrusted(
      ids,
      reason
    );
    Set<Id> retry = new Set<Id>();
    for (Id i : res.keySet()) {
      PMS_GuestErasureService.Result r = res.get(i);
      if (
        !r.success &&
        !r.blocked &&
        r.message != null &&
        r.message.startsWith('Anonymisation failed')
      ) {
        retry.add(i); // chunk was rolled back: isolate the bad guest
      }
    }
    for (Id i : retry) {
      res.put(
        i,
        PMS_GuestErasureService.anonymiseTrusted(new Set<Id>{ i }, reason)
          .get(i)
      );
    }
    Set<Id> review = new Set<Id>();
    for (Id i : res.keySet()) {
      PMS_GuestErasureService.Result r = res.get(i);
      if (r.success) {
        anonymised++;
      } else {
        review.add(i);
        if (r.blocked) {
          blocked++;
        } else {
          failed++;
          firstError = firstError == null ? r.message : firstError;
        }
      }
    }
    flag(review);
  }

  public void finish(Database.BatchableContext bc) {
    System.debug(
      LoggingLevel.INFO,
      'PMS retention (' +
        mode() +
        '): processed=' +
        processed +
        ' anonymised=' +
        anonymised +
        ' blocked=' +
        blocked +
        ' failed=' +
        failed +
        (firstError == null ? '' : ' firstError=' + firstError)
    );
  }

  private static void flag(Set<Id> ids) {
    if (ids.isEmpty()) {
      return;
    }
    List<Contact> upd = new List<Contact>();
    for (Contact c : [
      SELECT Id
      FROM Contact
      WHERE
        Id IN :ids
        AND PMS_Retention_Due__c = NULL
        AND PMS_Anonymised__c = FALSE
    ]) {
      upd.add(new Contact(Id = c.Id, PMS_Retention_Due__c = Date.today()));
    }
    update upd;
  }
}
