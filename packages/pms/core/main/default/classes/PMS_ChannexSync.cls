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

  public class Runner implements Queueable, Database.AllowsCallouts {
    private String stage;
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
      if (stage == PULL) {
        runPull();
      } else if (stage == ACK) {
        runAck();
      } else if (stage == PUSH) {
        runPush(null);
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
      if (!Test.isRunningTest()) {
        System.enqueueJob(next);
      }
    }
  }

  /** Pushes availability and rates for one site (siteId) or every connected site. Returns the logs saved. */
  public static List<PMS_Channel_Log__c> runPush(Id siteId) {
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

  private static void markPulled() {
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
