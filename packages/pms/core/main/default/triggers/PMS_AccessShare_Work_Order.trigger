/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Work_Order on PMS_Work_Order__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Work_Order__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
