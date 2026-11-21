trigger PMS_SpaceTrigger on PMS_Space__c(
  before insert,
  before update,
  before delete,
  after insert,
  after undelete
) {
  if (Trigger.isUndelete) {
    PMS_Entitlements.guardWrites(); // suspended: a restore is a write too
    return;
  }
  if (Trigger.isBefore && PMS_Entitlements.guardWrites()) {
    return; // suspended: every record already carries the licence error
  }
  if (Trigger.isBefore && Trigger.isInsert) {
    PMS_SpaceTriggerHandler.beforeInsert(Trigger.new);
  } else if (Trigger.isBefore && Trigger.isUpdate) {
    PMS_SpaceTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
  } else if (Trigger.isAfter) {
    PMS_SpaceTriggerHandler.afterInsert();
  }
}
