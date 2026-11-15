/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Time_Entry on PMS_Time_Entry__c(
  before insert,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Time_Entry__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
