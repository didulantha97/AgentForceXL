/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Pricing_Strategy on PMS_Pricing_Strategy__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Pricing_Strategy__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
