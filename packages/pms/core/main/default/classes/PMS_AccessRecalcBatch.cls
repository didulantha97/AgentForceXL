/**
 * Recalculates PMS Access Rule shares, one object after the other (each object is its own batch run,
 * chained from finish). Objects whose sharing default is Public Read/Write are skipped.
 */
public without sharing class PMS_AccessRecalcBatch implements Database.Batchable<SObject>, Database.Stateful {
  final List<String> objects;
  final Integer index;
  @TestVisible
  Integer errors = 0;
  Boolean blocked = false;

  public PMS_AccessRecalcBatch() {
    this(restrictedObjects(), 0);
  }

  public PMS_AccessRecalcBatch(List<String> objects, Integer index) {
    this.objects = objects;
    this.index = index;
  }

  public static List<String> restrictedObjects() {
    List<String> out = new List<String>();
    for (PMS_Access_Object__mdt c : PMS_AccessService.objectConfigs()) {
      if (PMS_AccessService.isRestricted(c.Object_API_Name__c)) {
        out.add(c.Object_API_Name__c);
      }
    }
    return out;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    if (PMS_Entitlements.jobsBlocked('PMS_AccessRecalcBatch')) {
      blocked = true; // suspended: no recalculation and no chaining
      return Database.getQueryLocator(
        [SELECT Id FROM PMS_Access_Team__c WHERE Id = NULL]
      );
    }
    if (objects.isEmpty() || index >= objects.size()) {
      return Database.getQueryLocator(
        [SELECT Id FROM PMS_Access_Team__c WHERE Id = NULL]
      );
    }
    return Database.getQueryLocator('SELECT Id FROM ' + objects[index]);
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    if (objects.isEmpty() || index >= objects.size()) {
      return;
    }
    Set<Id> ids = new Map<Id, SObject>(scope).keySet();
    PMS_AccessService.lastErrors.clear();
    PMS_AccessService.recalcRecords(objects[index], ids);
    errors += PMS_AccessService.lastErrors.size();
    for (String e : PMS_AccessService.lastErrors) {
      System.debug(LoggingLevel.ERROR, 'PMS access recalc: ' + e);
    }
  }

  public void finish(Database.BatchableContext bc) {
    if (!blocked && index + 1 < objects.size() && !Test.isRunningTest()) {
      Database.executeBatch(new PMS_AccessRecalcBatch(objects, index + 1), 200);
    }
  }
}
