/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Lease_Charge_Schedule on PMS_Lease_Charge_Schedule__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
