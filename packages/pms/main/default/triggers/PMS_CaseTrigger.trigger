/**
 * Case automation for the PMS. Today: the acknowledgement email for viewing requests made on the
 * public booking site (see PMS_GuestNotifications.viewingRequestsReceived).
 */
trigger PMS_CaseTrigger on Case(after insert) {
  PMS_GuestNotifications.viewingRequestsReceived(Trigger.new);
}
