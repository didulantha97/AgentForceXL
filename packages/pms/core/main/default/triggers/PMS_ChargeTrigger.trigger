trigger PMS_ChargeTrigger on PMS_Charge__c(
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
  PMS_FinanceTriggerHandler.onCharges(Trigger.new, Trigger.old);
}
