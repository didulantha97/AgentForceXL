/** Licence lock: PMS is read-only while the licence is suspended. Also feeds optional real-time Guest 360 stats. */
trigger PMS_Lock_Booking_Party on PMS_Booking_Party__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete,
  after undelete
) {
  if (Trigger.isAfter && !Trigger.isUndelete) {
    if (Trigger.isDelete) {
      PMS_GuestStatsQueueable.onPartyDelete(Trigger.old);
    } else {
      PMS_GuestStatsQueueable.onPartySave(Trigger.new, Trigger.oldMap);
    }
    return;
  }
  if (!PMS_Entitlements.guardWrites() && Trigger.isUndelete) {
    PMS_GuestStatsQueueable.onPartySave(Trigger.new, null);
  }
}
