/** Access Rule changes: make sure the team's group exists, then recalculate every restricted object. */
trigger PMS_AccessRuleTrigger on PMS_Access_Rule__c(
  after insert,
  after update,
  after delete,
  after undelete
) {
  Set<Id> teamIds = new Set<Id>();
  for (PMS_Access_Rule__c r : (Trigger.isDelete ? Trigger.old : Trigger.new)) {
    teamIds.add(r.Team__c);
  }
  System.enqueueJob(new PMS_AccessGroupSync(teamIds, true));
}
