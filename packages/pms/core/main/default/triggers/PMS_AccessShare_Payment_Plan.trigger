/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Payment_Plan on PMS_Payment_Plan__c(
  before insert,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Payment_Plan__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
