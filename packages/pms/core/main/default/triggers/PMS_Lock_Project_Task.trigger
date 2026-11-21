/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Project_Task on PMS_Project_Task__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
