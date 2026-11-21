/** Rent run: turns due lease charge schedules into Pending charges, then chains the invoice run. */
public with sharing class PMS_RecurringChargeBatch implements Database.Batchable<SObject> {
  private final Date runDate;
  private final Boolean chainInvoicing;
  private Boolean blocked = false;

  public PMS_RecurringChargeBatch() {
    this(Date.today(), true);
  }

  public PMS_RecurringChargeBatch(Date runDate, Boolean chainInvoicing) {
    this.runDate = runDate;
    this.chainInvoicing = chainInvoicing;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    if (PMS_Entitlements.jobsBlocked('PMS_RecurringChargeBatch')) {
      blocked = true;
      return Database.getQueryLocator(
        [SELECT Id FROM PMS_Lease_Charge_Schedule__c WHERE Id = NULL]
      );
    }
    Date d = runDate;
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Active__c,
          Amount__c,
          Charge_Type__c,
          Frequency__c,
          Start_Date__c,
          End_Date__c,
          Next_Run_Date__c,
          Escalation_Percent__c,
          Lease__c,
          Lease__r.Status__c,
          Lease__r.Account__c,
          Lease__r.Escalation_Percent__c
        FROM PMS_Lease_Charge_Schedule__c
        WHERE Active__c = TRUE AND Next_Run_Date__c <= :d
      ]
    );
  }

  public void execute(
    Database.BatchableContext bc,
    List<PMS_Lease_Charge_Schedule__c> scope
  ) {
    PMS_BillingService.generateRecurringCharges(scope, runDate);
  }

  public void finish(Database.BatchableContext bc) {
    if (chainInvoicing && !blocked && !Test.isRunningTest()) {
      Database.executeBatch(new PMS_InvoiceBatch(runDate), 100);
    }
  }
}
