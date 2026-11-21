/** Access Rule changes: make sure the team's group exists, then recalculate every restricted object. */
trigger PMS_AccessRuleTrigger on PMS_Access_Rule__c(
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
  Set<Id> teamIds = new Set<Id>();
  for (PMS_Access_Rule__c r : (Trigger.isDelete ? Trigger.old : Trigger.new)) {
    teamIds.add(r.Team__c);
  }
  System.enqueueJob(new PMS_AccessGroupSync(teamIds, true));
}
