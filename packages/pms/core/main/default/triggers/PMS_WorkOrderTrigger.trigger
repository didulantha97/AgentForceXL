trigger PMS_WorkOrderTrigger on PMS_Work_Order__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after undelete
) {
  if (Trigger.isUndelete) {
    PMS_Entitlements.guardWrites(); // suspended: a restore is a write too
    return;
  }
  if (Trigger.isBefore && PMS_Entitlements.guardWrites()) {
    return;
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    return;
  }
  if (Trigger.isBefore) {
    PMS_WorkOrderService.beforeWorkOrders(Trigger.new, Trigger.oldMap);
  } else {
    PMS_WorkOrderService.afterWorkOrders(Trigger.new, Trigger.oldMap);
  }
}
