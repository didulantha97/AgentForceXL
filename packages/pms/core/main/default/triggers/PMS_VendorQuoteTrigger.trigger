trigger PMS_VendorQuoteTrigger on PMS_Vendor_Quote__c(
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
  if (Trigger.isBefore) {
    PMS_Entitlements.guardWrites(); // suspended: read-only
    return;
  }
  PMS_WorkOrderService.afterQuotes(Trigger.new, Trigger.oldMap);
}
