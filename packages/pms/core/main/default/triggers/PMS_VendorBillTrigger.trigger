trigger PMS_VendorBillTrigger on PMS_Vendor_Bill__c(
  before insert,
  before update,
  before delete,
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
    PMS_WorkOrderService.beforeBills(Trigger.new);
  } else {
    PMS_WorkOrderService.afterBills(Trigger.new, Trigger.oldMap);
  }
}
