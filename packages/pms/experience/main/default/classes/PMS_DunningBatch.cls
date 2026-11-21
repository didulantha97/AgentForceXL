/**
 * Daily dunning run ("PMS Dunning (daily)"): marks overdue invoices Overdue, takes the next dunning
 * step where one is due, and keeps payment plans current. 20 invoices per chunk.
 *
 * Schedule (times are read in the scheduling user's time zone):
 *   System.schedule('PMS Dunning (daily)', '0 1 13 * * ?', new PMS_DunningBatch()); // 08:31 Stockholm for a Colombo user
 */
public without sharing class PMS_DunningBatch implements Database.Batchable<SObject>, Schedulable {
  public void execute(SchedulableContext ctx) {
    if (PMS_Entitlements.jobsBlocked('PMS_DunningBatch')) {
      return; // licence suspended: PMS is read-only
    }
    Database.executeBatch(new PMS_DunningBatch(), 20);
  }

  public Database.QueryLocator start(Database.BatchableContext ctx) {
    return Database.getQueryLocator(
      'SELECT Id FROM PMS_Invoice__c WHERE Balance__c > 0 AND Due_Date__c < TODAY ' +
      'AND Status__c NOT IN (\'Void\', \'Credited\', \'Draft\', \'Paid\') ORDER BY Due_Date__c'
    );
  }

  public void execute(
    Database.BatchableContext ctx,
    List<PMS_Invoice__c> scope
  ) {
    PMS_DunningService.process(
      new Map<Id, PMS_Invoice__c>(scope).keySet(),
      Date.today(),
      false
    );
  }

  public void finish(Database.BatchableContext ctx) {
    // Plans whose invoice got paid in full since the last run.
    List<PMS_Payment_Plan__c> done = [
      SELECT Id
      FROM PMS_Payment_Plan__c
      WHERE Status__c IN ('Proposed', 'Active') AND Invoice__r.Balance__c <= 0
      LIMIT 200
    ];
    for (PMS_Payment_Plan__c p : done) {
      p.Status__c = 'Completed';
    }
    if (!done.isEmpty()) {
      update done;
    }
  }
}
