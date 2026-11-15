/**
 * One scheduled entry point for the nightly PMS jobs.
 * Schedule once (Developer Console > Execute Anonymous):
 *   System.schedule('PMS Daily Jobs', '0 0 2 * * ?', new PMS_DailyJob());
 */
public with sharing class PMS_DailyJob implements Schedulable {
  public void execute(SchedulableContext sc) {
    if (PMS_ModuleConfig.isEnabled(PMS_ModuleConfig.HOTEL)) {
      Database.executeBatch(
        new PMS_NightAuditBatch(Date.today().addDays(-1)),
        200
      );
    }
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
