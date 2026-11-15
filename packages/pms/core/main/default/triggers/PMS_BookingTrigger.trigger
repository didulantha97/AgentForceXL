trigger PMS_BookingTrigger on PMS_Booking__c(
  before insert,
  before update,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore) {
    PMS_BookingTriggerHandler.beforeSave(Trigger.new, Trigger.oldMap);
  } else if (Trigger.isDelete) {
    PMS_BookingTriggerHandler.afterDelete(Trigger.old);
  } else {
    PMS_BookingTriggerHandler.afterSave(Trigger.new, Trigger.oldMap);
  }
}
