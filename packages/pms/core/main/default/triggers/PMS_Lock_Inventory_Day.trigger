/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Inventory_Day on PMS_Inventory_Day__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
