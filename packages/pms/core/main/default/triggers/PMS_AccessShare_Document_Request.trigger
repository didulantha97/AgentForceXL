/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Document_Request on PMS_Document_Request__c(
  before insert,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Document_Request__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
