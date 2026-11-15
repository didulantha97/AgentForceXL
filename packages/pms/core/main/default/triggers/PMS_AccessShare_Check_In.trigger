/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Check_In on PMS_Check_In__c(
  before insert,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Check_In__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
