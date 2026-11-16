/**
 * Booking trigger logic for guarantees (PMS_BookingGuaranteeTrigger).
 *
 *  - before update: a Confirmed or Active booking that becomes Cancelled or No Show gets
 *    Policy Pending + the time it happened. Tentative bookings (such as unpaid web holds being
 *    released) never get an automatic fee; staff can still apply the policy from the booking.
 *  - after update: pending policies are applied straight away by PMS_GuaranteeActionJob.
 *  - after insert: new bookings get a card or deposit link by email when their policy says so.
 *
 * Nothing is queued when no active payment policy exists, inside other async jobs (so their own job
 * chains are never blocked), or when the queueable limit is reached. PMS_GuaranteeJob runs hourly
 * and catches up on anything skipped.
 */
public without sharing class PMS_GuaranteeTriggerHandler {
  public static Boolean bypass = false;
  private static final Set<String> GUARANTEED = new Set<String>{
    'Confirmed',
    'Active'
  };
  private static final Set<String> FEE_STATUSES = new Set<String>{
    'Cancelled',
    'No Show'
  };
  private static Boolean policiesExist;

  public static void beforeUpdate(
    List<PMS_Booking__c> newList,
    Map<Id, PMS_Booking__c> oldMap
  ) {
    if (bypass) {
      return;
    }
    for (PMS_Booking__c b : newList) {
      PMS_Booking__c old = oldMap.get(b.Id);
      if (
        b.Status__c != old.Status__c &&
        FEE_STATUSES.contains(b.Status__c) &&
        GUARANTEED.contains(old.Status__c) &&
        b.Policy_Fee_Charged__c != true
      ) {
        b.Policy_Pending__c = true;
        b.Policy_Event_At__c = Datetime.now();
      }
    }
  }

  public static void afterInsert(List<PMS_Booking__c> newList) {
    if (bypass) {
      return;
    }
    Set<Id> ids = new Set<Id>();
    for (PMS_Booking__c b : newList) {
      if (
        b.Primary_Contact__c != null &&
        !PMS_GuaranteeJob.NO_LINK_CHANNELS.contains(b.Channel__c) &&
        b.Guarantee__c != 'Prepaid' &&
        b.Guarantee__c != 'Company Guarantee' &&
        !PMS_GuaranteeService.CLOSED.contains(b.Status__c) &&
        b.Status__c != 'Active'
      ) {
        ids.add(b.Id);
      }
    }
    enqueue(ids, PMS_GuaranteeActionJob.SEND_LINKS);
  }

  public static void afterUpdate(
    List<PMS_Booking__c> newList,
    Map<Id, PMS_Booking__c> oldMap
  ) {
    if (bypass) {
      return;
    }
    Set<Id> ids = new Set<Id>();
    for (PMS_Booking__c b : newList) {
      if (
        b.Policy_Pending__c == true &&
        oldMap.get(b.Id).Policy_Pending__c != true
      ) {
        ids.add(b.Id);
      }
    }
    enqueue(ids, PMS_GuaranteeActionJob.APPLY_POLICY);
  }

  private static void enqueue(Set<Id> ids, String action) {
    if (ids.isEmpty() || !anyPolicy()) {
      return;
    }
    if (
      System.isBatch() ||
      System.isFuture() ||
      System.isQueueable() ||
      System.isScheduled()
    ) {
      return;
    }
    if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
      return;
    }
    System.enqueueJob(new PMS_GuaranteeActionJob(action, ids));
  }

  private static Boolean anyPolicy() {
    if (policiesExist == null) {
      policiesExist =
        [
          SELECT COUNT()
          FROM PMS_Payment_Policy__c
          WHERE Active__c = TRUE
          LIMIT 1
        ] > 0;
    }
    return policiesExist;
  }
}
