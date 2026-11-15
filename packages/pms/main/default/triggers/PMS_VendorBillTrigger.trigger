trigger PMS_VendorBillTrigger on PMS_Vendor_Bill__c(
  before insert,
  before update,
  after update
) {
  if (Trigger.isBefore) {
    PMS_WorkOrderService.beforeBills(Trigger.new);
  } else {
    PMS_WorkOrderService.afterBills(Trigger.new, Trigger.oldMap);
  }
}
