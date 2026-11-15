trigger PMS_ChargeTrigger on PMS_Charge__c(
  after insert,
  after update,
  after delete,
  after undelete
) {
  PMS_FinanceTriggerHandler.onCharges(Trigger.new, Trigger.old);
}
