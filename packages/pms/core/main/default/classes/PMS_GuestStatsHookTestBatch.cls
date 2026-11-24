/** Test support: runs a Guest 360 hook inside a batch execute (Batchable cannot be an inner class). */
@IsTest
public class PMS_GuestStatsHookTestBatch implements Database.Batchable<SObject> {
  public static Id contactId;
  public static Integer jobsAfterHook;

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator('SELECT Id FROM Account LIMIT 1');
  }
  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    PMS_GuestStatsQueueable.onPartyDelete(
      new List<PMS_Booking_Party__c>{
        new PMS_Booking_Party__c(Contact__c = contactId)
      }
    );
    jobsAfterHook = Limits.getQueueableJobs();
  }
  public void finish(Database.BatchableContext bc) {
  }
}
