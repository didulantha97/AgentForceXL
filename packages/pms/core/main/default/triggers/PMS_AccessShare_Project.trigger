/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Project on PMS_Project__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Project__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
