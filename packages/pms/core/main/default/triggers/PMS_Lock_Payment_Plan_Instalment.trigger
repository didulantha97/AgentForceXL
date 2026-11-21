/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Payment_Plan_Instalment on PMS_Payment_Plan_Instalment__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
