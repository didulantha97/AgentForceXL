trigger PMS_PaymentTrigger on PMS_Payment__c(
  after insert,
  after update,
  after delete,
  after undelete
) {
  PMS_FinanceTriggerHandler.onPayments(Trigger.new, Trigger.old);
}
