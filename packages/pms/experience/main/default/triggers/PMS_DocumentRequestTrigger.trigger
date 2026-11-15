trigger PMS_DocumentRequestTrigger on PMS_Document_Request__c(
  after insert,
  after update
) {
  PMS_CustomerNotifications.documentsChanged(Trigger.new, Trigger.oldMap);
}
