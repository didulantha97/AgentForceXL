/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Rate on PMS_Rate__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
