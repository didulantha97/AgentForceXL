/**
 * Tests for the demo data loader (PMS_DemoData and its step classes, controller and callable).
 *
 * Packs load through chained Queueable jobs. A running job cannot chain another one in a test, so the loader
 * queues every step up front when Test.isRunningTest(); they run in order at Test.stopTest().
 * The baseline is loaded once in @testSetup (through the overdue-wave pack, which also proves that a pack loads
 * the baseline first when it is missing); each test method then works on that data.
 */
@IsTest
private class PMS_DemoDataTest {
  private static void allow() {
    PMS_DemoData.envOverride = 'allow';
    PMS_DemoData.adminOverride = true;
    PMS_DemoData.failAt = null;
  }

  private static PMS_DemoData.PackInfo pack(String key) {
    for (PMS_DemoData.PackInfo p : PMS_DemoData.status().packs) {
      if (p.key == key) {
        return p;
      }
    }
    return null;
  }

  private static Integer tracked(String pack, Schema.SObjectType type) {
    String name = type.getDescribe().getName();
    return [
      SELECT COUNT()
      FROM PMS_Demo_Record__c
      WHERE Pack__c = :pack AND Object_Name__c = :name
    ];
  }

  @TestSetup
  static void loadBaseline() {
    allow();
    Test.startTest();
    String msg = PMS_DemoData.load('overdue-wave');
    Test.stopTest();
    Assert.isTrue(msg.startsWith('Loading'), 'load started: ' + msg);
    Assert.isTrue(msg.contains('baseline'), 'baseline is loaded first: ' + msg);
    for (PMS_DemoData.PackInfo p : PMS_DemoData.status().packs) {
      Assert.areNotEqual(
        PMS_DemoData.FAILED,
        p.state,
        'Pack ' + p.key + ' failed: ' + p.message
      );
    }
  }

  // ------------------------------------------------------------------ what the baseline builds

  @IsTest
  static void baselineIsLoadedAndTracked() {
    allow();
    PMS_DemoData.PackInfo baseline = pack(PMS_DemoData.BASELINE);
    Assert.areEqual(
      PMS_DemoData.DONE,
      baseline.state,
      'baseline message: ' + baseline.message
    );
    Assert.isTrue(baseline.records > 400, 'records: ' + baseline.records);
    Assert.areEqual(PMS_DemoData.DONE, pack('overdue-wave').state);
    Assert.areEqual(PMS_DemoData.NONE, pack('busy-weekend').state);
    Assert.areEqual(12, tracked('overdue-wave', PMS_Invoice__c.SObjectType));
    Assert.areEqual(
      2,
      tracked('overdue-wave', PMS_Payment_Plan__c.SObjectType)
    );
    Assert.areEqual(
      12,
      tracked(PMS_DemoData.BASELINE, PMS_Space__c.SObjectType) -
      PMS_DemoData.UNITS,
      'twelve rooms plus eight units'
    );
    PMS_DemoData.Status st = PMS_DemoData.status();
    Assert.isTrue(st.allowed);
    Assert.isTrue(st.canRun);
    Assert.isFalse(st.busy);
    Assert.isFalse(st.counts.isEmpty());
    Assert.areEqual(
      [SELECT COUNT() FROM PMS_Demo_Record__c WHERE Object_Name__c != 'marker'],
      st.total
    );
    // Swedish sites, SEK
    Assert.isTrue(
      [
        SELECT COUNT()
        FROM PMS_Site__c
        WHERE Currency_Code__c = 'SEK' AND Country__c = 'Sweden'
      ] >= 4
    );
    // Room nights and inventory days came from the booking trigger, not from the loader
    Assert.isTrue([SELECT COUNT() FROM PMS_Room_Night__c] > 30);
    Assert.isTrue([SELECT COUNT() FROM PMS_Inventory_Day__c] > 100);
  }

  @IsTest
  static void loadingTwiceAddsNothing() {
    allow();
    Integer rows = [SELECT COUNT() FROM PMS_Demo_Record__c];
    Integer sites = [SELECT COUNT() FROM PMS_Site__c];
    Integer bookings = [SELECT COUNT() FROM PMS_Booking__c];
    String again = PMS_DemoData.load('baseline');
    Assert.isTrue(again.contains('already loaded'), again);
    Assert.areEqual(rows, [SELECT COUNT() FROM PMS_Demo_Record__c]);
    Assert.areEqual(sites, [SELECT COUNT() FROM PMS_Site__c]);
    Assert.areEqual(bookings, [SELECT COUNT() FROM PMS_Booking__c]);
  }

  /** Every KPI tile and every work queue of a module home must show something. */
  private static void assertHome(String module) {
    allow();
    PMS_HomeController.HomeData d = PMS_HomeController.getHome(module, null);
    Assert.isTrue(
      d.warnings.isEmpty(),
      module + ' home warnings: ' + d.warnings
    );
    Assert.isFalse(d.kpis.isEmpty(), module + ' has KPI tiles');
    for (PMS_HomeController.Kpi k : d.kpis) {
      Assert.isTrue(k.value > 0, module + ' KPI "' + k.key + '" is zero');
    }
    Assert.isFalse(d.sections.isEmpty(), module + ' has work queues');
    for (PMS_HomeController.Section s : d.sections) {
      Assert.isTrue(s.total > 0, module + ' queue "' + s.key + '" is empty');
    }
    Assert.isFalse(d.agenda.isEmpty(), module + ' agenda has entries');
  }

  /** Every attention item for the module must have rows (no warnings either). */
  private static void assertAttention(String module, Set<String> expected) {
    PMS_RevenueHomeController.Result r = PMS_RevenueHomeController.getAttention(
      module
    );
    Assert.isTrue(
      r.warnings.isEmpty(),
      module + ' attention warnings: ' + r.warnings
    );
    Set<String> seen = new Set<String>();
    for (PMS_RevenueHomeController.Item it : r.items) {
      seen.add(it.key);
      Assert.isTrue(
        it.count > 0,
        module + ' attention "' + it.key + '" is empty'
      );
    }
    Assert.areEqual(expected, seen, module + ' attention items');
  }

  @IsTest
  static void adminHomeIsFull() {
    assertHome('Admin');
    assertAttention(
      'Admin',
      new Set<String>{
        'cards',
        'holds',
        'fees',
        'refunds',
        'reminders',
        'instalments',
        'rent',
        'channelErrors',
        'otaUnassigned'
      }
    );
  }

  @IsTest
  static void hotelHomeIsFull() {
    assertHome('Hotel');
    assertAttention(
      'Hotel',
      new Set<String>{
        'cards',
        'holds',
        'fees',
        'refunds',
        'reminders',
        'instalments',
        'channelErrors',
        'otaUnassigned'
      }
    );
  }

  @IsTest
  static void propertyHomeIsFull() {
    assertHome('Property');
    assertAttention(
      'Property',
      new Set<String>{
        'cards',
        'holds',
        'fees',
        'refunds',
        'reminders',
        'instalments',
        'rent'
      }
    );
  }

  @IsTest
  static void projectsHomeIsFull() {
    assertHome('Projects');
    assertAttention('Projects', new Set<String>{ 'reminders', 'instalments' });
  }

  @IsTest
  static void practiceHomeIsFull() {
    assertHome('Practice');
    assertAttention(
      'Practice',
      new Set<String>{
        'cards',
        'holds',
        'fees',
        'refunds',
        'reminders',
        'instalments'
      }
    );
  }

  @IsTest
  static void noBlockingBookingOverlapsInTheBaseline() {
    allow();
    List<PMS_Booking__c> all = [
      SELECT Space__c, Start__c, End__c
      FROM PMS_Booking__c
      WHERE
        Space__c != NULL
        AND Status__c NOT IN :PMS_AvailabilityService.NON_BLOCKING_STATUSES
    ];
    for (Integer i = 0; i < all.size(); i++) {
      for (Integer j = i + 1; j < all.size(); j++) {
        Boolean clash =
          all[i].Space__c == all[j].Space__c &&
          all[i].Start__c < all[j].End__c &&
          all[i].End__c > all[j].Start__c;
        Assert.isFalse(clash, 'double booking in the demo data');
      }
    }
  }

  // ------------------------------------------------------------------ the other packs

  @IsTest
  static void everyPackLoads() {
    allow();
    Test.startTest();
    List<String> packs = new List<String>{
      'busy-weekend',
      'month-end',
      'channel-incident',
      'new-client'
    };
    for (String p : packs) {
      String msg = PMS_DemoData.load(p);
      Assert.isTrue(msg.startsWith('Loading'), p + ': ' + msg);
      Assert.isFalse(
        msg.contains('baseline pack is loaded first'),
        'baseline already there'
      );
    }
    Test.stopTest();
    for (String p : packs) {
      PMS_DemoData.PackInfo info = pack(p);
      Assert.areEqual(PMS_DemoData.DONE, info.state, p + ': ' + info.message);
      Assert.isTrue(info.records > 0, p + ' created records');
    }
    Integer weekend = tracked('busy-weekend', PMS_Booking__c.SObjectType);
    Assert.isTrue(
      weekend >= 8 && weekend <= 14,
      'busy-weekend bookings: ' + weekend
    );
    Assert.areEqual(
      1,
      tracked('month-end', PMS_Owner_Statement__c.SObjectType)
    );
    Assert.areEqual(6, tracked('month-end', PMS_Vendor_Bill__c.SObjectType));
    Assert.areEqual(
      4,
      tracked('month-end', PMS_Rent_Adjustment__c.SObjectType)
    );
    Assert.areEqual(
      6,
      tracked('channel-incident', PMS_Channel_Log__c.SObjectType)
    );
    Assert.areEqual(2, tracked('new-client', PMS_Matter__c.SObjectType));
    Assert.areEqual(3, tracked('new-client', PMS_Booking__c.SObjectType));
    Assert.areEqual(1, tracked('new-client', PMS_Project__c.SObjectType));
    // The weekend bookings went through the double-booking trigger: nothing overlaps
    List<PMS_Booking__c> blocking = [
      SELECT Space__c, Start__c, End__c
      FROM PMS_Booking__c
      WHERE
        Space__c != NULL
        AND Status__c NOT IN :PMS_AvailabilityService.NON_BLOCKING_STATUSES
    ];
    for (Integer i = 0; i < blocking.size(); i++) {
      for (Integer j = i + 1; j < blocking.size(); j++) {
        Assert.isFalse(
          blocking[i].Space__c == blocking[j].Space__c &&
            blocking[i].Start__c < blocking[j].End__c &&
            blocking[i].End__c > blocking[j].Start__c,
          'double booking after busy-weekend'
        );
      }
    }
  }

  // ------------------------------------------------------------------ reset

  @IsTest
  static void resettingOnePackLeavesTheRest() {
    allow();
    Integer baselineRows = pack(PMS_DemoData.BASELINE).records;
    Integer invoicesBefore = [SELECT COUNT() FROM PMS_Invoice__c];
    Test.startTest();
    String msg = PMS_DemoData.reset('overdue-wave');
    Test.stopTest();
    Assert.isTrue(msg.startsWith('Removing'), msg);
    PMS_DemoData.PackInfo wave = pack('overdue-wave');
    Assert.areEqual(
      PMS_DemoData.NONE,
      wave.state,
      'wave message: ' + wave.message
    );
    Assert.areEqual(0, wave.records);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Demo_Record__c WHERE Pack__c = 'overdue-wave']
    );
    Assert.areEqual(baselineRows, pack(PMS_DemoData.BASELINE).records);
    Assert.areEqual(PMS_DemoData.DONE, pack(PMS_DemoData.BASELINE).state);
    Assert.areEqual(invoicesBefore - 12, [SELECT COUNT() FROM PMS_Invoice__c]);
  }

  @IsTest
  static void resettingAllRemovesEverything() {
    allow();
    Set<Id> ids = new Set<Id>();
    for (PMS_Demo_Record__c r : [
      SELECT Record_Id__c
      FROM PMS_Demo_Record__c
      WHERE Object_Name__c != 'marker'
    ]) {
      ids.add((Id) r.Record_Id__c);
    }
    Assert.isFalse(ids.isEmpty());
    Test.startTest();
    String msg = PMS_DemoData.reset('all');
    Test.stopTest();
    Assert.isTrue(msg.startsWith('Removing'), msg);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Demo_Record__c],
      'tracking rows left'
    );
    Assert.areEqual(0, [SELECT COUNT() FROM PMS_Site__c WHERE Id IN :ids]);
    Assert.areEqual(0, [SELECT COUNT() FROM PMS_Booking__c WHERE Id IN :ids]);
    Assert.areEqual(0, [SELECT COUNT() FROM PMS_Invoice__c WHERE Id IN :ids]);
    Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE Id IN :ids]);
    Assert.areEqual(0, [SELECT COUNT() FROM Case WHERE Id IN :ids]);
    Assert.areEqual(PMS_DemoData.NONE, pack(PMS_DemoData.BASELINE).state);
    Assert.areEqual('Nothing to remove for "all".', PMS_DemoData.reset('all'));
  }

  @IsTest
  static void resettingTheBaselineRemovesEveryPack() {
    allow();
    Test.startTest();
    String msg = PMS_DemoData.reset('baseline');
    Test.stopTest();
    Assert.isTrue(msg.contains('removes every pack'), msg);
    Assert.areEqual(0, [SELECT COUNT() FROM PMS_Demo_Record__c]);
  }

  // ------------------------------------------------------------------ refusals

  @IsTest
  static void refusesInProduction() {
    PMS_DemoData.envOverride = 'deny';
    PMS_DemoData.adminOverride = true;
    Integer rows = [SELECT COUNT() FROM PMS_Demo_Record__c];
    Assert.isTrue(PMS_DemoData.load('new-client').startsWith('Refused'));
    Assert.isTrue(PMS_DemoData.reset('all').startsWith('Refused'));
    PMS_DemoData.Status st = PMS_DemoData.status();
    Assert.isFalse(st.allowed);
    Assert.isTrue(st.packs.isEmpty(), 'nothing is revealed when not allowed');
    Assert.isTrue(st.reason.contains('production'), st.reason);
    Assert.areEqual(rows, [SELECT COUNT() FROM PMS_Demo_Record__c]);
    Assert.isFalse(PMS_DemoDataController.getStatus().allowed);
  }

  @IsTest
  static void refusesNonAdmins() {
    PMS_DemoData.envOverride = 'allow';
    PMS_DemoData.adminOverride = false;
    Assert.isTrue(PMS_DemoData.load('new-client').startsWith('Refused'));
    Assert.isTrue(PMS_DemoData.reset('overdue-wave').startsWith('Refused'));
    PMS_DemoData.Status st = PMS_DemoData.status();
    Assert.isFalse(st.allowed);
    Assert.isTrue(st.reason.contains('administrators'), st.reason);
  }

  @IsTest
  static void refusesWhileTheLicenceIsSuspended() {
    allow();
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    try {
      Assert.isTrue(PMS_DemoData.load('new-client').startsWith('Refused'));
      Assert.isTrue(PMS_DemoData.reset('overdue-wave').startsWith('Refused'));
      PMS_DemoData.Status st = PMS_DemoData.status();
      Assert.isTrue(st.allowed, 'the card still shows');
      Assert.isFalse(st.canRun, 'but nothing can start');
      Assert.isNotNull(st.reason);
    } finally {
      PMS_Entitlements.forceStateForTest(null);
    }
  }

  @IsTest
  static void rejectsUnknownPacksAndBusyStates() {
    allow();
    Assert.isTrue(PMS_DemoData.load('nope').startsWith('Unknown pack'));
    Assert.isTrue(PMS_DemoData.reset('nope').startsWith('Unknown pack'));
    Assert.isTrue(
      PMS_DemoData.load('  BASELINE ').contains('already loaded'),
      'names are trimmed and case-insensitive'
    );
    Assert.areEqual(
      'Nothing to remove for "busy-weekend".',
      PMS_DemoData.reset('busy-weekend')
    );
  }

  @IsTest
  static void realEnvironmentAndAdminChecksRun() {
    // No overrides: the real Organization and permission checks must at least run without error.
    PMS_DemoData.envOverride = null;
    PMS_DemoData.adminOverride = null;
    String env = PMS_DemoData.environmentProblem();
    Assert.isTrue(env == null || env.contains('production'), 'env: ' + env);
    Assert.isNotNull(PMS_DemoData.isAdmin());
    PMS_DemoData.licenceProblem();
    PMS_DemoData.blockReason();
  }

  // ------------------------------------------------------------------ failure handling

  @IsTest
  static void aFailedStepRollsBackAndCanBeReset() {
    allow();
    PMS_DemoData.failAt = 'incident';
    Test.startTest();
    PMS_DemoData.load('channel-incident');
    Test.stopTest();
    PMS_DemoData.failAt = null;
    PMS_DemoData.PackInfo info = pack('channel-incident');
    Assert.areEqual(PMS_DemoData.FAILED, info.state);
    Assert.isTrue(info.message.contains('Forced failure'), info.message);
    Assert.areEqual(0, info.records, 'the failed step left nothing behind');
    String again = PMS_DemoData.load('channel-incident');
    Assert.isTrue(again.contains('did not load completely'), again);
    // Resetting clears the failure marker, so the pack can be loaded again
    Assert.areEqual(
      'DONE',
      PMS_DemoData.resetPass(new List<String>{ 'channel-incident' })
    );
    Assert.areEqual(PMS_DemoData.NONE, pack('channel-incident').state);
  }

  @IsTest
  static void aStepNeedsTheBaseline() {
    allow();
    PMS_DemoData.Ctx c = new PMS_DemoData.Ctx('x');
    Assert.isNotNull(c.ref('s.hotel'));
    Assert.isNull(c.opt('nope'));
    try {
      c.ref('nope');
      Assert.fail('a missing record must fail loudly');
    } catch (PMS_DemoData.DemoException e) {
      Assert.isTrue(e.getMessage().contains('Load the baseline pack first'));
    }
    try {
      PMS_DemoData.runStep(new List<String>{ 'x:unknown' }, 0);
    } catch (Exception e) {
      Assert.fail('a bad step is recorded, not thrown: ' + e.getMessage());
    }
    Assert.isTrue(pack(PMS_DemoData.BASELINE).records > 0);
  }

  // ------------------------------------------------------------------ controller and callable

  @IsTest
  static void controllerReturnsStatusAndMessages() {
    allow();
    PMS_DemoData.Status st = PMS_DemoDataController.getStatus();
    Assert.isTrue(st.allowed);
    Assert.areEqual(6, st.packs.size());
    PMS_DemoData.Status loaded = PMS_DemoDataController.load('baseline');
    Assert.isTrue(loaded.message.contains('already loaded'), loaded.message);
    PMS_DemoData.Status gone = PMS_DemoDataController.reset('busy-weekend');
    Assert.isTrue(gone.message.startsWith('Nothing to remove'), gone.message);
  }

  @IsTest
  static void callableLoadsResetsAndReportsStatus() {
    allow();
    Callable api = new PMS_DemoDataApi();
    Assert.areEqual(false, api.call('status', new Map<String, Object>()));
    Assert.isTrue(
      String.valueOf(
          api.call('load', new Map<String, Object>{ 'pack' => 'baseline' })
        )
        .contains('already loaded')
    );
    Assert.isTrue(
      String.valueOf(
          api.call('reset', new Map<String, Object>{ 'pack' => 'busy-weekend' })
        )
        .startsWith('Nothing')
    );
    Assert.isTrue(
      String.valueOf(api.call('load', null)).startsWith('Unknown pack')
    );
    try {
      api.call('explode', null);
      Assert.fail('unknown action must throw');
    } catch (PMS_DemoData.DemoException e) {
      Assert.isTrue(e.getMessage().contains('explode'));
    }
  }

  /**
   * Developer Edition and trial orgs stop a Queueable chain after 5 jobs ("Maximum stack depth has been
   * reached"). The tests queue every step up front, so they never chained; this exercises the chaining itself.
   */
  @IsTest
  static void chainingFallsBackToASchedulerAtTheDepthLimit() {
    allow();
    List<String> plan = new List<String>{ 'x:core', 'x:hotel' };
    Test.startTest();
    PMS_DemoData.forceMaxDepth = true;
    PMS_DemoData.chainNext(plan, 1);
    PMS_DemoData.forceMaxDepth = false;
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name LIKE 'PMS demo data step 1%'
      ],
      'the next step is scheduled'
    );
    Test.stopTest();
  }

  @IsTest
  static void shortChainsGetSeveralStepsPerJob() {
    // Developer Edition / trial: 5 chained jobs for the 9 baseline steps
    Integer left = 9;
    for (Integer depth = 1; depth <= 5; depth++) {
      left -= PMS_DemoData.stepsPerJob(left, depth, 5);
    }
    Assert.areEqual(0, left, 'a 9 step plan fits in a chain of 5');
    Assert.areEqual(
      1,
      PMS_DemoData.stepsPerJob(9, 1, 50),
      'long chains run one step per job'
    );
    Assert.areEqual(1, PMS_DemoData.stepsPerJob(1, 5, 5));
    Assert.areEqual(
      2,
      PMS_DemoData.stepsPerJob(9, 1, null),
      'unknown maximum assumes 5'
    );
  }
}
