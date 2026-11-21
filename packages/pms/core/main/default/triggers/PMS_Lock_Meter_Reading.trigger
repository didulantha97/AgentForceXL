/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Meter_Reading on PMS_Meter_Reading__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
