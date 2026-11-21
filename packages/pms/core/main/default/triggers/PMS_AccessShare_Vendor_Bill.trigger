/** PMS access engine: keeps PMS Access Rule shares current when a record is created or moves site. */
trigger PMS_AccessShare_Vendor_Bill on PMS_Vendor_Bill__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update
) {
  PMS_AccessService.handleTrigger(
    'PMS_Vendor_Bill__c',
    Trigger.isAfter,
    Trigger.new,
    Trigger.oldMap
  );
}
