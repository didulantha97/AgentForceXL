/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Budget_Line on PMS_Budget_Line__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
