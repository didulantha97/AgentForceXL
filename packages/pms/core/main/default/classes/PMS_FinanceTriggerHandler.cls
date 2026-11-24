/** Keeps invoice and booking totals current whenever charges or payments change. */
public without sharing class PMS_FinanceTriggerHandler {
  public static void onCharges(
    List<PMS_Charge__c> newList,
    List<PMS_Charge__c> oldList
  ) {
    PMS_GuestStatsQueueable.onCharges(newList, oldList); // no-op unless real-time stats are on
    Set<Id> invoiceIds = new Set<Id>();
    Set<Id> bookingIds = new Set<Id>();
    for (
      List<PMS_Charge__c> l : new List<List<PMS_Charge__c>>{ newList, oldList }
    ) {
      if (l == null) {
        continue;
      }
      for (PMS_Charge__c c : l) {
        invoiceIds.add(c.Invoice__c);
        bookingIds.add(c.Booking__c);
      }
    }
    PMS_BillingService.recalcInvoices(invoiceIds);
    PMS_BillingService.recalcBookings(bookingIds);
  }

  public static void onPayments(
    List<PMS_Payment__c> newList,
    List<PMS_Payment__c> oldList
  ) {
    Set<Id> invoiceIds = new Set<Id>();
    Set<Id> bookingIds = new Set<Id>();
    for (
      List<PMS_Payment__c> l : new List<List<PMS_Payment__c>>{
        newList,
        oldList
      }
    ) {
      if (l == null) {
        continue;
      }
      for (PMS_Payment__c p : l) {
        invoiceIds.add(p.Invoice__c);
        bookingIds.add(p.Booking__c);
      }
    }
    invoiceIds.remove(null);
    if (!invoiceIds.isEmpty()) {
      for (PMS_Invoice__c inv : [
        SELECT Booking__c
        FROM PMS_Invoice__c
        WHERE Id IN :invoiceIds
      ]) {
        bookingIds.add(inv.Booking__c);
      }
    }
    PMS_BillingService.recalcInvoices(invoiceIds);
    PMS_BillingService.recalcBookings(bookingIds);
  }
}
