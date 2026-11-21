/** Licence lock: PMS is read-only while the licence is suspended. */
trigger PMS_Lock_Booking_Party on PMS_Booking_Party__c(
  before insert,
  before update,
  before delete,
  after undelete
) {
  PMS_Entitlements.guardWrites();
}
