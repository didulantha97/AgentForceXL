trigger PMS_VendorQuoteTrigger on PMS_Vendor_Quote__c(
  after insert,
  after update
) {
  PMS_WorkOrderService.afterQuotes(Trigger.new, Trigger.oldMap);
}
