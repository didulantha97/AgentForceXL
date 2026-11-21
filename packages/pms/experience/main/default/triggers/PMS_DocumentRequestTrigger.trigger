trigger PMS_DocumentRequestTrigger on PMS_Document_Request__c(
  after insert,
  after update,
  after undelete
) {
  if (PMS_Entitlements.guardWrites()) {
    return;
  }
  if (Trigger.isUndelete) {
    return;
  }
  PMS_CustomerNotifications.documentsChanged(Trigger.new, Trigger.oldMap);
}
