trigger PMS_WorkOrderTrigger on PMS_Work_Order__c(
  before insert,
  before update,
  after insert,
  after update
) {
  if (Trigger.isBefore) {
    PMS_WorkOrderService.beforeWorkOrders(Trigger.new, Trigger.oldMap);
  } else {
    PMS_WorkOrderService.afterWorkOrders(Trigger.new, Trigger.oldMap);
  }
}
