/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Rate_Plan on PMS_Rate_Plan__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Rate_Plan__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
