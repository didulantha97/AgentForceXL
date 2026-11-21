/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Room_Night on PMS_Room_Night__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
