/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Resource on PMS_Resource__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
