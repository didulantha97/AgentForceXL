/**
 * Nightly owner-statement refresh. For every active site with an owner, refreshes the Draft statement
 * for the current month and, on the 1st to 5th, for the previous month (so late payments and bills land
 * before staff publish it). Published and Paid statements are never changed.
 *
 * Schedule once (03:30 in the running user's time zone):  PMS_OwnerStatementJob.scheduleNightly();
 * Run now:                                                 Database.executeBatch(new PMS_OwnerStatementJob(), 10);
 */
@NamespaceAccessible
public without sharing class PMS_OwnerStatementJob implements Schedulable, Database.Batchable<SObject> {
  @NamespaceAccessible
  public static final String JOB_NAME = 'PMS Owner Statements (nightly)';
  @TestVisible
  private Date today;

  @NamespaceAccessible
  public PMS_OwnerStatementJob() {
    this(Date.today());
  }

  @NamespaceAccessible
  public PMS_OwnerStatementJob(Date today) {
    this.today = today;
  }

  @NamespaceAccessible
  public void execute(SchedulableContext sc) {
    if (PMS_Entitlements.jobsBlocked('PMS_OwnerStatementJob')) {
      return; // licence suspended: PMS is read-only
    }
    Database.executeBatch(new PMS_OwnerStatementJob(), 10);
  }

  @NamespaceAccessible
  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM PMS_Site__c
        WHERE Owner_Account__c != NULL AND Status__c = 'Active'
      ]
    );
  }

  @NamespaceAccessible
  public void execute(Database.BatchableContext bc, List<PMS_Site__c> scope) {
    PMS_OwnerStatementService.generate(today, scope);
    if (today.day() <= 5) {
      PMS_OwnerStatementService.generate(
        today.toStartOfMonth().addDays(-1),
        scope
      );
    }
  }

  @NamespaceAccessible
  public void finish(Database.BatchableContext bc) {
  }

  @NamespaceAccessible
  public static Id scheduleNightly() {
    return System.schedule(
      JOB_NAME,
      '0 30 3 * * ?',
      new PMS_OwnerStatementJob()
    );
  }
}
