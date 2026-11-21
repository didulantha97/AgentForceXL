/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Payment_Policy on PMS_Payment_Policy__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
