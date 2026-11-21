/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Index_Value on PMS_Index_Value__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
