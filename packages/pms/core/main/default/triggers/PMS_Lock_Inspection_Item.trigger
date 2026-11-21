/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Inspection_Item on PMS_Inspection_Item__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
