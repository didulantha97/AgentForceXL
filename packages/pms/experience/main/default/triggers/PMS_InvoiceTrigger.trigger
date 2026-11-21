/** Confirms public-site bookings as soon as their prepayment invoice is paid. */
trigger PMS_InvoiceTrigger on PMS_Invoice__c(after update, after undelete) {
  if (PMS_Entitlements.guardWrites()) {
    return;
  }
  if (Trigger.isUndelete) {
    return;
  }
  Set<Id> bookingIds = new Set<Id>();
  for (PMS_Invoice__c inv : Trigger.new) {
    PMS_Invoice__c old = Trigger.oldMap.get(inv.Id);
    if (
      inv.Status__c == 'Paid' &&
      old.Status__c != 'Paid' &&
      inv.Booking__c != null
    ) {
      bookingIds.add(inv.Booking__c);
    }
  }
  if (!bookingIds.isEmpty()) {
    PMS_WebBookingHold.confirmPaid(bookingIds);
  }
}
