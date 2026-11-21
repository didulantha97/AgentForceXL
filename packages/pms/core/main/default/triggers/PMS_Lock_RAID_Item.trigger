/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_RAID_Item on PMS_RAID_Item__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
