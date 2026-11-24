/**
 * Guest 360 stats refresh, started from PMS_DailyJob (the single scheduled entry point). Runs in phases chained
 * from finish(), each phase a separate batch over a different driver:
 *  PRIMARY    Contacts that are the primary contact of a booking (incremental: booking modified since the cutoff)
 *  PARTY      Contacts on a booking party (incremental: party row or its booking modified since the cutoff)
 *  STALE      full only: Contacts that already have stats (catches guests whose bookings were deleted / detached)
 *  CHARGE     incremental only: bookings with a charge modified since the cutoff -> their primary contacts
 *  DEPARTURE  incremental only: stays that departed since the cutoff without being modified -> primary + party contacts
 *  ARRIVAL    incremental only: Contacts whose stored Next Arrival is today or earlier (so it never goes stale)
 * Full backfill = PRIMARY + PARTY + STALE. Safe to rerun: each Contact is recomputed from source.
 *
 * Watermark and status live in the protected setting PMS_Guest_Stats_Run__c. The incremental cutoff is
 * Last_Success__c (fallback: 25 hours ago); it only advances to this run's start when no error occurred.
 *
 * Backfill once:  Database.executeBatch(new PMS_GuestStatsBatch(true), 100);
 * "Today" uses the running user's time zone, which must match the property's.
 *
 * without sharing: writes the read-only stats fields for every guest, whoever runs the job. Documented for
 * security review.
 */
public without sharing class PMS_GuestStatsBatch implements Database.Batchable<SObject>, Database.Stateful {
  @TestVisible
  private static final String PRIMARY = 'PRIMARY';
  @TestVisible
  private static final String PARTY = 'PARTY';
  @TestVisible
  private static final String STALE = 'STALE';
  @TestVisible
  private static final String CHARGE = 'CHARGE';
  @TestVisible
  private static final String DEPARTURE = 'DEPARTURE';
  @TestVisible
  private static final String ARRIVAL = 'ARRIVAL';
  public static final Integer SCOPE_SIZE = 100;

  private final Boolean fullBackfill;
  private final Datetime since;
  private final String phase;
  private final Datetime runStart;
  private Integer errorCount;
  private String firstError;

  public PMS_GuestStatsBatch(Boolean fullBackfill) {
    this(fullBackfill, defaultCutoff(), PRIMARY, Datetime.now(), 0, null);
  }

  public PMS_GuestStatsBatch(
    Boolean fullBackfill,
    Datetime since,
    String phase
  ) {
    this(fullBackfill, since, phase, Datetime.now(), 0, null);
  }

  public PMS_GuestStatsBatch(
    Boolean fullBackfill,
    Datetime since,
    String phase,
    Datetime runStart,
    Integer errorCount,
    String firstError
  ) {
    this.fullBackfill = fullBackfill == true;
    this.since = since == null ? Datetime.now().addHours(-25) : since;
    this.phase = phase == null ? PRIMARY : phase;
    this.runStart = runStart == null ? Datetime.now() : runStart;
    this.errorCount = errorCount == null ? 0 : errorCount;
    this.firstError = firstError;
  }

  private static Datetime defaultCutoff() {
    Datetime ok = PMS_Guest_Stats_Run__c.getOrgDefaults().Last_Success__c;
    return ok == null ? Datetime.now().addHours(-25) : ok;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    Datetime cutoff = since;
    Date today = Date.today();
    Datetime todayStart = Datetime.newInstance(
      today,
      Time.newInstance(0, 0, 0, 0)
    );
    List<String> completed = PMS_GuestStatsService.COMPLETED_STATUSES;
    if (phase == PRIMARY) {
      return fullBackfill
        ? Database.getQueryLocator(
            [
              SELECT Id
              FROM Contact
              WHERE
                Id IN (
                  SELECT Primary_Contact__c
                  FROM PMS_Booking__c
                  WHERE Primary_Contact__c != NULL
                )
            ]
          )
        : Database.getQueryLocator(
            [
              SELECT Id
              FROM Contact
              WHERE
                Id IN (
                  SELECT Primary_Contact__c
                  FROM PMS_Booking__c
                  WHERE
                    Primary_Contact__c != NULL
                    AND LastModifiedDate >= :cutoff
                )
            ]
          );
    }
    if (phase == PARTY) {
      return fullBackfill
        ? Database.getQueryLocator(
            [
              SELECT Id
              FROM Contact
              WHERE
                Id IN (
                  SELECT Contact__c
                  FROM PMS_Booking_Party__c
                  WHERE Contact__c != NULL
                )
            ]
          )
        : Database.getQueryLocator(
            [
              SELECT Id
              FROM Contact
              WHERE
                Id IN (
                  SELECT Contact__c
                  FROM PMS_Booking_Party__c
                  WHERE
                    Contact__c != NULL
                    AND (LastModifiedDate >= :cutoff
                    OR Booking__r.LastModifiedDate >= :cutoff)
                )
            ]
          );
    }
    if (phase == STALE) {
      return Database.getQueryLocator(
        [SELECT Id FROM Contact WHERE PMS_Stats_Refreshed__c != NULL]
      );
    }
    if (phase == CHARGE) {
      return Database.getQueryLocator(
        [
          SELECT Id, Primary_Contact__c
          FROM PMS_Booking__c
          WHERE
            Primary_Contact__c != NULL
            AND Id IN (
              SELECT Booking__c
              FROM PMS_Charge__c
              WHERE LastModifiedDate >= :cutoff
            )
        ]
      );
    }
    if (phase == DEPARTURE) {
      return Database.getQueryLocator(
        [
          SELECT Id, Primary_Contact__c
          FROM PMS_Booking__c
          WHERE
            Status__c IN :completed
            AND End__c >= :cutoff
            AND End__c < :todayStart
        ]
      );
    }
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Contact
        WHERE PMS_Next_Arrival__c != NULL AND PMS_Next_Arrival__c <= :today
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    Set<Id> contactIds = new Set<Id>();
    Set<Id> bookingIds = new Set<Id>();
    for (SObject so : scope) {
      if (so instanceof PMS_Booking__c) {
        contactIds.add(((PMS_Booking__c) so).Primary_Contact__c);
        bookingIds.add(so.Id);
      } else {
        contactIds.add(so.Id);
      }
    }
    try {
      if (phase == DEPARTURE && !bookingIds.isEmpty()) {
        for (PMS_Booking_Party__c p : [
          SELECT Contact__c
          FROM PMS_Booking_Party__c
          WHERE Booking__c IN :bookingIds AND Contact__c != NULL
        ]) {
          contactIds.add(p.Contact__c);
        }
      }
      for (String msg : PMS_GuestStatsService.recalcWithErrors(contactIds)) {
        recordError(msg);
      }
    } catch (Exception e) {
      // One bad chunk must not stop the remaining chunks; the cutoff is not advanced, so the next run retries it.
      System.debug(
        LoggingLevel.ERROR,
        'PMS guest stats chunk failed (' + phase + '): ' + e.getMessage()
      );
      recordError(phase + ': ' + e.getMessage());
    }
  }

  public void finish(Database.BatchableContext bc) {
    if (bc != null && bc.getJobId() != null) {
      for (AsyncApexJob j : [
        SELECT NumberOfErrors, ExtendedStatus
        FROM AsyncApexJob
        WHERE Id = :bc.getJobId()
      ]) {
        if (j.NumberOfErrors > 0) {
          // execute() catches its own exceptions, so these are failures outside that handler (e.g. limits)
          errorCount += j.NumberOfErrors;
          if (firstError == null) {
            firstError = j.ExtendedStatus;
          }
        }
      }
    }
    String next = nextPhase();
    if (next != null && !Test.isRunningTest()) {
      try {
        Database.executeBatch(
          new PMS_GuestStatsBatch(
            fullBackfill,
            since,
            next,
            runStart,
            errorCount,
            firstError
          ),
          SCOPE_SIZE
        );
        return;
      } catch (Exception e) {
        errorCount++;
        firstError = firstError == null
          ? 'Could not start phase ' + next + ': ' + e.getMessage()
          : firstError;
      }
    } else if (next != null) {
      return; // tests run one phase at a time
    }
    writeStatus();
  }

  private void recordError(String msg) {
    errorCount++;
    if (firstError == null) {
      firstError = msg;
    }
  }

  private void writeStatus() {
    try {
      PMS_Guest_Stats_Run__c s = PMS_Guest_Stats_Run__c.getOrgDefaults();
      s.Last_Run__c = Datetime.now();
      s.Last_Error_Count__c = errorCount;
      s.Last_Error__c = firstError == null ? null : firstError.left(255);
      if (errorCount == 0) {
        s.Last_Success__c = runStart; // only a clean run moves the watermark
      }
      upsert s;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS guest stats status not saved: ' + e.getMessage()
      );
    }
  }

  @TestVisible
  private String nextPhase() {
    if (fullBackfill) {
      return phase == PRIMARY ? PARTY : (phase == PARTY ? STALE : null);
    }
    if (phase == PRIMARY) {
      return PARTY;
    }
    if (phase == PARTY) {
      return CHARGE;
    }
    if (phase == CHARGE) {
      return DEPARTURE;
    }
    return phase == DEPARTURE ? ARRIVAL : null;
  }
}
