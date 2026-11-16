/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Rent_Adjustment on PMS_Rent_Adjustment__c(
  before insert,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Rent_Adjustment__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
