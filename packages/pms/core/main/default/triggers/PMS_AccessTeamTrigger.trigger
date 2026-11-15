/** Access Team changes: re-sync the team's group; recalculate shares when the team's reach changes. */
trigger PMS_AccessTeamTrigger on PMS_Access_Team__c(
  after insert,
  after update,
  after delete,
  after undelete
) {
  Set<Id> ids = new Set<Id>();
  Boolean recalc = Trigger.isInsert || Trigger.isDelete || Trigger.isUndelete;
  for (PMS_Access_Team__c t : (Trigger.isDelete ? Trigger.old : Trigger.new)) {
    ids.add(t.Id);
    if (Trigger.isUpdate) {
      PMS_Access_Team__c o = Trigger.oldMap.get(t.Id);
      if (
        o.Active__c != t.Active__c ||
        o.All_Internal_Users__c != t.All_Internal_Users__c
      ) {
        recalc = true;
      }
    }
  }
  System.enqueueJob(new PMS_AccessGroupSync(ids, recalc));
}
