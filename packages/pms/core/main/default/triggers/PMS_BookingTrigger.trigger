trigger PMS_BookingTrigger on PMS_Booking__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete,
  after undelete
) {
  if (Trigger.isUndelete) {
    PMS_Entitlements.guardWrites(); // suspended: a restore is a write too
    return;
  }
  if (Trigger.isBefore && PMS_Entitlements.guardWrites()) {
    return; // suspended: every record already carries the licence error
  }
  if (Trigger.isBefore) {
    if (!Trigger.isDelete) {
      PMS_BookingTriggerHandler.beforeSave(Trigger.new, Trigger.oldMap);
    }
  } else if (Trigger.isDelete) {
    PMS_BookingTriggerHandler.afterDelete(Trigger.old);
  } else {
    PMS_BookingTriggerHandler.afterSave(Trigger.new, Trigger.oldMap);
  }
}
