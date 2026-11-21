/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Pricing_Factor on PMS_Pricing_Factor__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
