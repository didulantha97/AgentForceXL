/** Access Team changes: re-sync the team's group; recalculate shares when the team's reach changes. */
trigger PMS_AccessTeamTrigger on PMS_Access_Team__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete,
  after undelete
) {
  if (Trigger.isUndelete && PMS_Entitlements.guardWrites()) {
    return; // suspended: a restore is a write too
  }
  if (Trigger.isBefore) {
    PMS_Entitlements.guardWrites(); // suspended: read-only
    return;
  }
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
