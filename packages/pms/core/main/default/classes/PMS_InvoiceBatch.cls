/** Invoice run: groups Pending charges into invoices per bill-to account and booking/project/matter. */
public with sharing class PMS_InvoiceBatch implements Database.Batchable<SObject> {
  private final Date issueDate;

  public PMS_InvoiceBatch() {
    this(Date.today());
  }

  public PMS_InvoiceBatch(Date issueDate) {
    this.issueDate = issueDate;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      PMS_BillingService.pendingChargeQuery() +
      ' ORDER BY Account__c, Booking__c'
    );
  }

  public void execute(Database.BatchableContext bc, List<PMS_Charge__c> scope) {
    PMS_BillingService.invoicePendingCharges(scope, issueDate);
  }

  public void finish(Database.BatchableContext bc) {
  }
}
