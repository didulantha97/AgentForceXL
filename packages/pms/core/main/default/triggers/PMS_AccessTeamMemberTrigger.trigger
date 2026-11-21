/** Access Team Member changes: one user per team, then re-sync the team's group and Hide permission sets. */
trigger PMS_AccessTeamMemberTrigger on PMS_Access_Team_Member__c(
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
    if (PMS_Entitlements.guardWrites() || Trigger.isDelete) {
      return; // suspended: read-only (or nothing to validate on delete)
    }
    for (PMS_Access_Team_Member__c m : Trigger.new) {
      if (m.User__c == null) {
        m.User__c.addError('Choose a user.');
        continue;
      }
      m.Unique_Key__c =
        String.valueOf(m.Team__c).left(15) + String.valueOf(m.User__c).left(15);
    }
    return;
  }
  Set<Id> teamIds = new Set<Id>();
  for (
    PMS_Access_Team_Member__c m : (Trigger.isDelete ? Trigger.old : Trigger.new)
  ) {
    teamIds.add(m.Team__c);
  }
  System.enqueueJob(new PMS_AccessGroupSync(teamIds, false));
}
