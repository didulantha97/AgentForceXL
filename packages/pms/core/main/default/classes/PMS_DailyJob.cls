/**
 * One scheduled entry point for the nightly PMS jobs.
 * Schedule once (Developer Console > Execute Anonymous):
 *   System.schedule('PMS Daily Jobs', '0 0 2 * * ?', new PMS_DailyJob());
 *
 * Time zone: "today" in the nightly jobs (including Guest 360 stats) uses the scheduling user's time zone, which
 * must match the property's time zone.
 */
public with sharing class PMS_DailyJob implements Schedulable {
  public void execute(SchedulableContext sc) {
    try {
      PMS_Entitlements.ensureInstallDate(); // safety net: records the pilot start if the install script missed it
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'PMS install date not recorded: ' + e.getMessage()
      );
    }
    if (PMS_Entitlements.jobsBlocked('PMS_DailyJob')) {
      return; // licence suspended: PMS is read-only
    }
    if (PMS_ModuleConfig.isEnabled(PMS_ModuleConfig.HOTEL)) {
      Database.executeBatch(
        new PMS_NightAuditBatch(Date.today().addDays(-1)),
        200
      );
    }
    // Guest 360 stats: incremental nightly; full rebuild on Sundays (corrects deleted bookings / swapped guests)
    // and on every run until one has succeeded (first-install backfill in subscriber orgs).
    Boolean fullGuestStats =
      Datetime.newInstance(Date.today(), Time.newInstance(12, 0, 0, 0))
        .format('u') == '7' ||
      PMS_Guest_Stats_Run__c.getOrgDefaults()?.Last_Success__c == null;
    Database.executeBatch(new PMS_GuestStatsBatch(fullGuestStats), 100);
    if (PMS_ModuleConfig.isEnabled(PMS_ModuleConfig.PROPERTY)) {
      Database.executeBatch(
        new PMS_RecurringChargeBatch(Date.today(), true),
        200
      );
    } else {
      Database.executeBatch(new PMS_InvoiceBatch(Date.today()), 100);
    }
  }
}
