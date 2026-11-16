trigger PMS_BookingGuaranteeTrigger on PMS_Booking__c(
  before update,
  after insert,
  after update
) {
  if (Trigger.isBefore && Trigger.isUpdate) {
    PMS_GuaranteeTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
  } else if (Trigger.isAfter && Trigger.isInsert) {
    PMS_GuaranteeTriggerHandler.afterInsert(Trigger.new);
  } else if (Trigger.isAfter && Trigger.isUpdate) {
    PMS_GuaranteeTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
  }
}
