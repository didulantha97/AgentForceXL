/**
 * Channex sync, every 15 minutes ("PMS Channex Sync :02/:17/:32/:47") and on demand. Salesforce allows
 * no callout after a DML statement in the same transaction, so each run is a short chain:
 *
 *   PULL  callout: booking revisions feed -> DML: create / modify / cancel bookings, logs
 *   ACK   callouts: acknowledge the revisions that were saved -> DML: logs (then PULL again when the
 *         feed had a full page, otherwise PUSH)
 *   PUSH  per connected site: build availability and rates (queries) -> 2 callouts -> DML: logs,
 *         last push time
 *
 * Nothing runs while PMS Settings > Channex Enabled is unticked.
 *
 * Licence suspended: PULL and ACK still run (inbound OTA bookings are saved and acknowledged; the Runner sets
 * PMS_Entitlements.allowInbound for the whole stage so the bookkeeping updates are not blocked either, unless
 * the owner switched Allow_Inbound_When_Suspended__c off, in which case PULL is skipped). PUSH sends a one-time
 * stop-sell per site instead of availability and rates, then pauses; see PMS_ChannexAri.
 */
public without sharing class PMS_ChannexSync implements Schedulable {
  public static final String PULL = 'PULL';
  public static final String ACK = 'ACK';
  public static final String PUSH = 'PUSH';

  public static Boolean enabled() {
    PMS_Settings__c s = PMS_Settings__c.getOrgDefaults();
    return s != null && s.Channex_Enabled__c == true;
  }

  public void execute(SchedulableContext ctx) {
    if (enabled()) {
      System.enqueueJob(new Runner(PULL));
    }
  }

  @TestVisible
  private static Runner lastChained; // the stage queued last (the chain itself does not run in tests)

  public class Runner implements Queueable, Database.AllowsCallouts {
    @TestVisible
    private String stage;
    @TestVisible
    private List<String> ackIds;
    private Boolean more = false;
    private Integer pullRounds = 0;

    public Runner(String stage) {
      this.stage = stage;
    }

    public void execute(QueueableContext ctx) {
      if (!enabled()) {
        return;
      }
      if (stage == PUSH) {
        runPush(null);
        return;
      }
      if (stage == PULL && !PMS_Entitlements.inboundEnabled()) {
        chain(new Runner(PUSH)); // suspended and the owner refuses inbound: nothing to save, go on to the stop-sell
        return;
      }
      // PULL and ACK: OTA bookings that already exist on the channel must be saved and acknowledged even when
      // the licence is suspended, including the bookkeeping DML (logs, Channex_Last_Pull__c). Always restored.
      Boolean previousInbound = PMS_Entitlements.allowInbound;
      PMS_Entitlements.allowInbound = true;
      try {
        if (stage == PULL) {
          runPull();
        } else if (stage == ACK) {
          runAck();
        }
      } finally {
        PMS_Entitlements.allowInbound = previousInbound;
      }
    }

    private void runPull() {
      List<PMS_Channel_Log__c> logs = new List<PMS_Channel_Log__c>();
      PMS_ChannexBookings.Outcome o;
      try {
        List<Map<String, Object>> feed = PMS_ChannexBookings.fetchFeed();
        o = PMS_ChannexBookings.process(feed);
        logs.addAll(o.logs);
      } catch (Exception e) {
        logs.add(
          new PMS_Channel_Log__c(
            Direction__c = 'Inbound',
            Kind__c = 'Error',
            Status__c = 'Error',
            Message__c = ('Fetching bookings failed: ' + e.getMessage())
              .left(255)
          )
        );
      }
      if (!logs.isEmpty()) {
        insert logs;
      }
      markPulled();
      Runner next;
      if (o != null && !o.ackIds.isEmpty()) {
        next = new Runner(ACK);
        next.ackIds = o.ackIds;
        next.more = o.more;
        next.pullRounds = pullRounds;
      } else {
        next = new Runner(PUSH);
      }
      chain(next);
    }

    private void runAck() {
      List<PMS_Channel_Log__c> logs = PMS_ChannexBookings.acknowledge(
        ackIds == null ? new List<String>() : ackIds
      );
      if (!logs.isEmpty()) {
        insert logs;
      }
      Runner next;
      if (more == true && pullRounds < 5) {
        next = new Runner(PULL);
        next.pullRounds = pullRounds + 1;
      } else {
        next = new Runner(PUSH);
      }
      chain(next);
    }

    private void chain(Runner next) {
      lastChained = next;
      if (!Test.isRunningTest()) {
        System.enqueueJob(next);
      }
    }
  }

  /** Pushes availability and rates for one site (siteId) or every connected site. Returns the logs saved. */
  public static List<PMS_Channel_Log__c> runPush(Id siteId) {
    if (PMS_Entitlements.isLocked()) {
      return runStopSell(siteId);
    }
    List<PMS_Site__c> sites = siteId == null
      ? [
          SELECT Id
          FROM PMS_Site__c
          WHERE Channex_Property_Id__c != NULL
          LIMIT 20
        ]
      : [
          SELECT Id
          FROM PMS_Site__c
          WHERE Id = :siteId AND Channex_Property_Id__c != NULL
        ];
    Date today = Date.today();
    Integer days = PMS_ChannexAri.horizon();
    Map<Id, PMS_ChannexAri.Payload> payloads = new Map<Id, PMS_ChannexAri.Payload>();
    for (PMS_Site__c s : sites) {
      payloads.put(s.Id, PMS_ChannexAri.build(s.Id, today, days));
    }
    List<PMS_Channel_Log__c> logs = new List<PMS_Channel_Log__c>();
    for (Id id : payloads.keySet()) {
      logs.addAll(PMS_ChannexAri.push(id, payloads.get(id)));
    }
    if (!logs.isEmpty()) {
      insert logs;
    }
    List<PMS_Site__c> stamps = new List<PMS_Site__c>();
    for (Id id : payloads.keySet()) {
      stamps.add(
        new PMS_Site__c(Id = id, Channex_Last_Push__c = Datetime.now())
      );
    }
    if (!stamps.isEmpty()) {
      update stamps;
    }
    return logs;
  }

  /**
   * Suspended: close every mapped room type once per site. Callouts first, then the log rows (Channel Log is
   * the one object the licence lock never blocks). Site timestamps are not touched: the lock would reject them.
   */
  private static List<PMS_Channel_Log__c> runStopSell(Id siteId) {
    Set<Id> siteIds = new Map<Id, PMS_Site__c>(
        siteId == null
          ? [
              SELECT Id
              FROM PMS_Site__c
              WHERE Channex_Property_Id__c != NULL
              LIMIT 20
            ]
          : [
              SELECT Id
              FROM PMS_Site__c
              WHERE Id = :siteId AND Channex_Property_Id__c != NULL
            ]
      )
      .keySet();
    List<PMS_Channel_Log__c> logs = new List<PMS_Channel_Log__c>();
    if (siteIds.isEmpty()) {
      return logs;
    }
    siteIds.removeAll(PMS_ChannexAri.stopSellSent(siteIds));
    if (siteIds.isEmpty()) {
      return logs; // already closed on the channel: nothing is repeated every run
    }
    Map<Id, PMS_ChannexAri.Payload> payloads = PMS_ChannexAri.buildStopSell(
      siteIds,
      Date.today(),
      PMS_ChannexAri.horizon()
    );
    for (Id id : payloads.keySet()) {
      logs.addAll(PMS_ChannexAri.pushStopSell(id, payloads.get(id)));
    }
    if (!logs.isEmpty()) {
      insert logs;
    }
    return logs;
  }

  private static void markPulled() {
    if (PMS_Entitlements.isLocked() && !PMS_Entitlements.inboundAccepted()) {
      return; // suspended without the inbound exemption: the site update would be rejected and roll the pull back
    }
    List<PMS_Site__c> sites = [
      SELECT Id
      FROM PMS_Site__c
      WHERE Channex_Property_Id__c != NULL
      LIMIT 50
    ];
    for (PMS_Site__c s : sites) {
      s.Channex_Last_Pull__c = Datetime.now();
    }
    if (!sites.isEmpty()) {
      update sites;
    }
  }

  /** Schedules the four 15-minute runs (call once). */
  public static void scheduleAll() {
    for (String minute : new List<String>{ '2', '17', '32', '47' }) {
      System.schedule(
        'PMS Channex Sync :' + minute.leftPad(2, '0'),
        '0 ' + minute + ' * * * ?',
        new PMS_ChannexSync()
      );
    }
  }
}
