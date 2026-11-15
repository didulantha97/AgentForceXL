trigger PMS_ApprovalRequestTrigger on PMS_Approval_Request__c(
  before insert,
  before update,
  after insert,
  after update
) {
  if (Trigger.isBefore) {
    PMS_CustomerNotifications.beforeApprovals(Trigger.new);
  } else {
    PMS_CustomerNotifications.approvalsChanged(Trigger.new, Trigger.oldMap);
  }
}
