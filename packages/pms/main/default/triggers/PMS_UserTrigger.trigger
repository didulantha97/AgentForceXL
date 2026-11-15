/** Gives new customer portal users the PMS Stripe Access permission set, so Pay now works. */
trigger PMS_UserTrigger on User(after insert, after update) {
  PMS_PortalUserSetup.onUsers(Trigger.new, Trigger.oldMap);
}
