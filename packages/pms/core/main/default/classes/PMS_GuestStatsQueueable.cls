/**
 * Near-real-time Guest 360 stats (optional, OFF by default: PMS_Settings__c.Guest_Stats_Realtime__c).
 * Trigger handlers call the on* methods, which do nothing (no SOQL, no DML) while the switch is off. When on, they
 * collect the affected Contacts (old and new values of lookups) and Bookings, then enqueue a Queueable that
 * resolves bookings to their primary and party Contacts and calls PMS_GuestStatsService.recalc in chunks of 100,
 * chaining itself for the rest. Within one call ids are de-duplicated; recalcBookings updates only
 * unwatched fields so it never re-enqueues. There is no cross-call
 * dedupe on purpose: a rolled-back first attempt must not suppress the retry's job.
 *
 * Never blocks a save: every entry point catches and logs. Skipped (the nightly batch catches up) in batch and
 * future context and when the queueable limit is reached.
 *
 * without sharing: stats fields are read-only and written for every guest regardless of the saving user.
 */
public without sharing class PMS_GuestStatsQueueable implements Queueable {
  public static final Integer CHUNK_SIZE = 100;
  private static final Integer RESOLVE_LIMIT = 5000;

  @TestVisible
  private static Boolean enabledOverride;
  private static Boolean enabledCache;

  private final Set<Id> contactIds;
  private final Set<Id> bookingIds;

  public PMS_GuestStatsQueueable(Set<Id> contactIds, Set<Id> bookingIds) {
    this.contactIds = contactIds == null ? new Set<Id>() : contactIds;
    this.bookingIds = bookingIds == null ? new Set<Id>() : bookingIds;
  }

  public static Boolean isEnabled() {
    if (enabledOverride != null) {
      return enabledOverride;
    }
    if (enabledCache == null) {
      enabledCache =
        PMS_Settings__c.getOrgDefaults().Guest_Stats_Realtime__c == true;
    }
    return enabledCache;
  }

  // ------------------------------------------------------------ trigger hooks

  public static void onBookingSave(
    List<PMS_Booking__c> newList,
    Map<Id, PMS_Booking__c> oldMap
  ) {
    try {
      if (!isEnabled() || newList == null) {
        return;
      }
      Set<Id> contacts = new Set<Id>();
      Set<Id> bookings = new Set<Id>();
      for (PMS_Booking__c b : newList) {
        PMS_Booking__c old = oldMap == null ? null : oldMap.get(b.Id);
        if (
          old == null ||
          old.Status__c != b.Status__c ||
          old.Start__c != b.Start__c ||
          old.End__c != b.End__c ||
          old.Primary_Contact__c != b.Primary_Contact__c
        ) {
          contacts.add(b.Primary_Contact__c);
          if (old != null) {
            contacts.add(old.Primary_Contact__c);
            bookings.add(b.Id); // party contacts resolved in the job
          }
        }
      }
      enqueue(contacts, bookings);
    } catch (Exception e) {
      logError(e);
    }
  }

  /** Before delete (party rows are still readable): primary and party contacts. One SOQL, only when enabled. */
  public static void onBookingBeforeDelete(List<PMS_Booking__c> oldList) {
    try {
      if (!isEnabled() || oldList == null) {
        return;
      }
      Set<Id> contacts = new Set<Id>();
      for (PMS_Booking__c b : oldList) {
        contacts.add(b.Primary_Contact__c);
      }
      for (PMS_Booking_Party__c p : [
        SELECT Contact__c
        FROM PMS_Booking_Party__c
        WHERE Booking__c IN :oldList
        LIMIT :RESOLVE_LIMIT
      ]) {
        contacts.add(p.Contact__c);
      }
      enqueue(contacts, null);
    } catch (Exception e) {
      logError(e);
    }
  }

  public static void onPartySave(
    List<PMS_Booking_Party__c> newList,
    Map<Id, PMS_Booking_Party__c> oldMap
  ) {
    try {
      if (!isEnabled() || newList == null) {
        return;
      }
      Set<Id> contacts = new Set<Id>();
      for (PMS_Booking_Party__c p : newList) {
        PMS_Booking_Party__c old = oldMap == null ? null : oldMap.get(p.Id);
        if (old == null || old.Contact__c != p.Contact__c) {
          contacts.add(p.Contact__c);
          if (old != null) {
            contacts.add(old.Contact__c);
          }
        }
      }
      enqueue(contacts, null);
    } catch (Exception e) {
      logError(e);
    }
  }

  public static void onPartyDelete(List<PMS_Booking_Party__c> oldList) {
    try {
      if (!isEnabled() || oldList == null) {
        return;
      }
      Set<Id> contacts = new Set<Id>();
      for (PMS_Booking_Party__c p : oldList) {
        contacts.add(p.Contact__c);
      }
      enqueue(contacts, null);
    } catch (Exception e) {
      logError(e);
    }
  }

  /** Charges: newList is Trigger.new (null on delete), oldList is Trigger.old (null on insert/undelete). */
  public static void onCharges(
    List<PMS_Charge__c> newList,
    List<PMS_Charge__c> oldList
  ) {
    try {
      if (!isEnabled()) {
        return;
      }
      Map<Id, PMS_Charge__c> oldById = new Map<Id, PMS_Charge__c>();
      if (oldList != null && newList != null) {
        for (PMS_Charge__c c : oldList) {
          if (c.Id != null) {
            oldById.put(c.Id, c);
          }
        }
      }
      Set<Id> bookings = new Set<Id>();
      if (newList != null) {
        for (PMS_Charge__c c : newList) {
          PMS_Charge__c old = oldById.get(c.Id);
          if (
            old == null ||
            old.Net_Amount__c != c.Net_Amount__c ||
            old.Status__c != c.Status__c ||
            old.Charge_Type__c != c.Charge_Type__c ||
            old.Booking__c != c.Booking__c
          ) {
            bookings.add(c.Booking__c);
            if (old != null) {
              bookings.add(old.Booking__c);
            }
          }
        }
      } else if (oldList != null) {
        for (PMS_Charge__c c : oldList) {
          bookings.add(c.Booking__c);
        }
      }
      enqueue(null, bookings);
    } catch (Exception e) {
      logError(e);
    }
  }

  // ------------------------------------------------------------ enqueue

  private static void enqueue(Set<Id> contacts, Set<Id> bookings) {
    Set<Id> c = new Set<Id>();
    Set<Id> b = new Set<Id>();
    if (contacts != null) {
      c.addAll(contacts);
    }
    if (bookings != null) {
      b.addAll(bookings);
    }
    c.remove(null);
    b.remove(null);
    if (c.isEmpty() && b.isEmpty()) {
      return;
    }
    // Never enqueue from async contexts: a Queueable may add only one child job, and taking it would make the
    // caller's own chaining (e.g. PMS_ChannexSync.Runner) throw an uncatchable LimitException and roll back
    // the whole sync. The nightly batch catches up on anything skipped here.
    if (
      System.isBatch() ||
      System.isFuture() ||
      System.isQueueable() ||
      System.isScheduled() ||
      Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()
    ) {
      return;
    }
    System.enqueueJob(new PMS_GuestStatsQueueable(c, b));
  }

  // ------------------------------------------------------------ job

  public void execute(QueueableContext ctx) {
    try {
      Set<Id> all = new Set<Id>(contactIds);
      if (!bookingIds.isEmpty()) {
        for (PMS_Booking__c b : [
          SELECT Primary_Contact__c
          FROM PMS_Booking__c
          WHERE Id IN :bookingIds
          LIMIT :RESOLVE_LIMIT
        ]) {
          all.add(b.Primary_Contact__c);
        }
        for (PMS_Booking_Party__c p : [
          SELECT Contact__c
          FROM PMS_Booking_Party__c
          WHERE Booking__c IN :bookingIds
          LIMIT :RESOLVE_LIMIT
        ]) {
          all.add(p.Contact__c);
        }
      }
      all.remove(null);
      List<Id> ordered = new List<Id>(all);
      Set<Id> chunk = new Set<Id>();
      Set<Id> rest = new Set<Id>();
      for (Integer i = 0; i < ordered.size(); i++) {
        if (i < CHUNK_SIZE) {
          chunk.add(ordered[i]);
        } else {
          rest.add(ordered[i]);
        }
      }
      List<String> errors = PMS_GuestStatsService.recalcWithErrors(chunk);
      Integer failures = errors.size();
      String first = errors.isEmpty() ? null : errors[0];
      if (!rest.isEmpty() && !Test.isRunningTest()) {
        Boolean chained = false;
        try {
          if (!System.isQueueable() || !AsyncInfo.hasMaxStackDepth()) {
            System.enqueueJob(new PMS_GuestStatsQueueable(rest, null));
            chained = true;
          }
        } catch (AsyncException e) {
          System.debug(
            LoggingLevel.INFO,
            'PMS guest stats chain: ' + e.getMessage()
          );
        }
        if (!chained) {
          failures += rest.size();
          first = first == null
            ? rest.size() +
              ' guests not refreshed in real time (job chain limit); the nightly job will catch up'
            : first;
        }
      }
      if (failures > 0) {
        recordFailures(failures, first);
      }
    } catch (Exception e) {
      logError(e);
      recordFailures(1, e.getMessage());
    }
  }

  /** Adds to the error count on the run-status setting; leaves Last_Success__c (the batch watermark) alone. */
  @TestVisible
  private static void recordFailures(Integer count, String firstError) {
    try {
      PMS_Guest_Stats_Run__c s = PMS_Guest_Stats_Run__c.getOrgDefaults();
      s.Last_Error_Count__c =
        (s.Last_Error_Count__c == null ? 0 : s.Last_Error_Count__c) + count;
      if (firstError != null) {
        s.Last_Error__c = ('Real-time: ' + firstError).left(255);
      }
      upsert s;
    } catch (Exception e) {
      logError(e);
    }
  }

  private static void logError(Exception e) {
    System.debug(
      LoggingLevel.ERROR,
      'PMS_GuestStatsQueueable: ' +
        e.getMessage() +
        ' ' +
        e.getStackTraceString()
    );
  }
}
