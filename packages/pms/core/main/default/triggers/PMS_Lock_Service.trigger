/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Service on PMS_Service__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
