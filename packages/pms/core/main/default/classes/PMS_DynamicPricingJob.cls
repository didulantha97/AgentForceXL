/**
 * Hourly: recalculates every active pricing strategy ("PMS Dynamic Pricing (hourly)").
 *   System.schedule('PMS Dynamic Pricing (hourly)', '0 25 * * * ?', new PMS_DynamicPricingJob());
 * Each strategy runs in its own queueable, so one failing strategy never blocks the others and each
 * gets its own limits.
 */
public without sharing class PMS_DynamicPricingJob implements Schedulable {
  public void execute(SchedulableContext ctx) {
    if (PMS_Entitlements.jobsBlocked('PMS_DynamicPricingJob')) {
      return; // licence suspended: PMS is read-only
    }
    List<Id> ids = new List<Id>(
      new Map<Id, PMS_Pricing_Strategy__c>(
          [SELECT Id FROM PMS_Pricing_Strategy__c WHERE Active__c = TRUE]
        )
        .keySet()
    );
    if (!ids.isEmpty()) {
      System.enqueueJob(new Runner(ids));
    }
  }

  public class Runner implements Queueable {
    private List<Id> pending;

    public Runner(List<Id> pending) {
      this.pending = pending;
    }

    public void execute(QueueableContext ctx) {
      if (pending == null || pending.isEmpty()) {
        return;
      }
      Id current = pending.remove(0);
      try {
        PMS_DynamicPricingService.recalculate(current);
      } catch (Exception e) {
        update new PMS_Pricing_Strategy__c(
          Id = current,
          Last_Run_At__c = Datetime.now(),
          Last_Run_Result__c = PMS_DynamicPricingService.cut(
            'Failed: ' + e.getMessage(),
            255
          )
        );
      }
      if (!pending.isEmpty() && !Test.isRunningTest()) {
        System.enqueueJob(new Runner(pending));
      }
    }
  }
}
