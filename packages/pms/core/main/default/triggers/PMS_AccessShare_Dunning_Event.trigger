/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Dunning_Event on PMS_Dunning_Event__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Dunning_Event__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
