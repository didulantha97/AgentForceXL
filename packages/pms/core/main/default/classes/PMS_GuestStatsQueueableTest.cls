@isTest
private class PMS_GuestStatsQueueableTest {
  /** Does nothing; used to fill the queueable limit. */
  private class FillerJob implements Queueable {
    public void execute(QueueableContext ctx) {
    }
  }

  private static Id hookContactId;
  private static Integer queueableJobs;
  private static Integer scheduledJobs;

  /** Runs a hook from inside a Queueable (System.isQueueable() is true). */
  private class HookQueueable implements Queueable {
    public void execute(QueueableContext ctx) {
      PMS_GuestStatsQueueable.onPartyDelete(
        new List<PMS_Booking_Party__c>{
          new PMS_Booking_Party__c(Contact__c = hookContactId)
        }
      );
      queueableJobs = Limits.getQueueableJobs();
    }
  }

  /** Runs a hook from inside a Schedulable (System.isScheduled() is true). */
  private class HookSchedulable implements Schedulable {
    public void execute(SchedulableContext ctx) {
      PMS_GuestStatsQueueable.onPartyDelete(
        new List<PMS_Booking_Party__c>{
          new PMS_Booking_Party__c(Contact__c = hookContactId)
        }
      );
      scheduledJobs = Limits.getQueueableJobs();
    }
  }

  private static Contact guest(String lastName) {
    return PMS_TestDataFactory.contact(
      PMS_TestDataFactory.account('Acc ' + lastName).Id,
      lastName
    );
  }

  private static Datetime at(Integer dayOffset) {
    return Datetime.newInstance(
      Date.today().addDays(dayOffset),
      Time.newInstance(12, 0, 0, 0)
    );
  }

  private static PMS_Booking__c booking(Id primary, String status) {
    return new PMS_Booking__c(
      Primary_Contact__c = primary,
      Status__c = status,
      Start__c = at(-10),
      End__c = at(-7)
    );
  }

  private static PMS_Booking__c insertBooking(Id primary, String status) {
    PMS_Booking__c b = booking(primary, status);
    insert b;
    return b;
  }

  private static PMS_Charge__c charge(Id bookingId) {
    return new PMS_Charge__c(
      Booking__c = bookingId,
      Charge_Type__c = 'Room Night',
      Quantity__c = 1,
      Unit_Price__c = 100,
      Status__c = 'Pending'
    );
  }

  private static Contact reload(Id id) {
    return [
      SELECT PMS_Total_Stays__c, PMS_Stats_Refreshed__c
      FROM Contact
      WHERE Id = :id
    ];
  }

  private static void assertRefreshed(Id id, String label) {
    Assert.isNotNull(reload(id).PMS_Stats_Refreshed__c, label);
  }

  private static void assertNotRefreshed(Id id, String label) {
    Assert.isNull(reload(id).PMS_Stats_Refreshed__c, label);
  }

  /** Common start: entitlements DEV, hooks off while data is built. */
  private static void arrange() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    PMS_GuestStatsQueueable.enabledOverride = false;
  }

  // ------------------------------------------------------------ toggle off

  @isTest
  static void toggleOffEnqueuesNothing() {
    arrange();
    Contact c = guest('OffA');
    Contact other = guest('OffB');
    Test.startTest();
    PMS_Booking__c b = insertBooking(c.Id, 'Confirmed');
    b.Status__c = 'Cancelled';
    update b;
    b.Primary_Contact__c = other.Id;
    update b;
    PMS_Booking_Party__c p = new PMS_Booking_Party__c(
      Booking__c = b.Id,
      Contact__c = c.Id
    );
    insert p;
    delete p;
    PMS_Charge__c ch = charge(b.Id);
    insert ch;
    delete ch;
    delete b;
    undelete b;
    Assert.areEqual(0, Limits.getQueueableJobs(), 'No job while off');
    Test.stopTest();
    assertNotRefreshed(c.Id, 'No stats written while off');
    assertNotRefreshed(other.Id, 'No stats written while off');
  }

  @isTest
  static void toggleOffHooksDoNoSoqlOrDml() {
    arrange();
    Contact c = guest('OffHook');
    PMS_Booking__c b = insertBooking(c.Id, 'Confirmed');
    PMS_Booking_Party__c p = new PMS_Booking_Party__c(
      Booking__c = b.Id,
      Contact__c = c.Id
    );
    insert p;
    PMS_Charge__c ch = charge(b.Id);
    insert ch;
    Test.startTest();
    Integer q = Limits.getQueries();
    Integer d = Limits.getDmlStatements();
    PMS_GuestStatsQueueable.onBookingSave(new List<PMS_Booking__c>{ b }, null);
    PMS_GuestStatsQueueable.onBookingBeforeDelete(
      new List<PMS_Booking__c>{ b }
    );
    PMS_GuestStatsQueueable.onPartySave(
      new List<PMS_Booking_Party__c>{ p },
      null
    );
    PMS_GuestStatsQueueable.onPartyDelete(new List<PMS_Booking_Party__c>{ p });
    PMS_GuestStatsQueueable.onCharges(new List<PMS_Charge__c>{ ch }, null);
    PMS_GuestStatsQueueable.onCharges(null, new List<PMS_Charge__c>{ ch });
    Assert.areEqual(q, Limits.getQueries(), 'No SOQL from hooks while off');
    Assert.areEqual(d, Limits.getDmlStatements(), 'No DML from hooks');
    Assert.areEqual(0, Limits.getQueueableJobs());
    Test.stopTest();
  }

  @isTest
  static void settingIsOffByDefaultAndCachedPerTransaction() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    PMS_GuestStatsQueueable.enabledOverride = null;
    Assert.isFalse(PMS_GuestStatsQueueable.isEnabled(), 'Off by default');
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Guest_Stats_Realtime__c = true
    );
    // cached within the transaction, so the first answer stands
    Assert.isFalse(PMS_GuestStatsQueueable.isEnabled());
  }

  @isTest
  static void settingOnEnqueues() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    PMS_GuestStatsQueueable.enabledOverride = null;
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Guest_Stats_Realtime__c = true
    );
    Contact c = guest('SettingOn');
    Assert.isTrue(PMS_GuestStatsQueueable.isEnabled());
    Test.startTest();
    insertBooking(c.Id, 'Completed');
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Assert.areEqual(1, reload(c.Id).PMS_Total_Stays__c);
  }

  // ------------------------------------------------------------ bookings

  @isTest
  static void bookingInsertUpdatesStats() {
    arrange();
    Contact c = guest('Ins');
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    insertBooking(c.Id, 'Completed');
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Contact r = reload(c.Id);
    Assert.areEqual(1, r.PMS_Total_Stays__c);
    Assert.isNotNull(r.PMS_Stats_Refreshed__c);
  }

  @isTest
  static void bookingStatusChangeRecalculates() {
    arrange();
    Contact c = guest('Status');
    PMS_Booking__c b = insertBooking(c.Id, 'Confirmed');
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    b.Status__c = 'Cancelled';
    update b;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Contact r = reload(c.Id);
    Assert.isNotNull(r.PMS_Stats_Refreshed__c);
    Assert.areEqual(0, r.PMS_Total_Stays__c, 'Cancelled does not count');
  }

  @isTest
  static void unwatchedBookingFieldChangeDoesNotEnqueue() {
    arrange();
    Contact c = guest('Unwatched');
    PMS_Booking__c b = insertBooking(c.Id, 'Confirmed');
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    b.Special_Requests__c = 'Quiet room';
    update b;
    Assert.areEqual(0, Limits.getQueueableJobs());
    Test.stopTest();
    assertNotRefreshed(c.Id, 'Nothing queued');
  }

  @isTest
  static void primaryContactChangeRecalculatesOldAndNew() {
    arrange();
    Contact oldC = guest('OldPrimary');
    Contact newC = guest('NewPrimary');
    PMS_Booking__c b = insertBooking(oldC.Id, 'Completed');
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    b.Primary_Contact__c = newC.Id;
    update b;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Contact o = reload(oldC.Id);
    Contact n = reload(newC.Id);
    Assert.isNotNull(o.PMS_Stats_Refreshed__c, 'Old contact recalculated');
    Assert.isNotNull(n.PMS_Stats_Refreshed__c, 'New contact recalculated');
    Assert.areEqual(0, o.PMS_Total_Stays__c);
    Assert.areEqual(1, n.PMS_Total_Stays__c);
  }

  @isTest
  static void bookingDeleteRecalculatesPrimary() {
    arrange();
    Contact c = guest('Del');
    PMS_Booking__c b = insertBooking(c.Id, 'Completed');
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    delete b;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Contact r = reload(c.Id);
    Assert.isNotNull(r.PMS_Stats_Refreshed__c);
    Assert.areEqual(0, r.PMS_Total_Stays__c);
  }

  @isTest
  static void bookingUndeleteRecalculatesPrimary() {
    arrange();
    Contact c = guest('Undel');
    PMS_Booking__c b = insertBooking(c.Id, 'Completed');
    delete b;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    undelete b;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Assert.areEqual(1, reload(c.Id).PMS_Total_Stays__c);
  }

  @isTest
  static void bulkBookingInsertQueuesOneJob() {
    arrange();
    Contact c = guest('Bulk');
    List<PMS_Booking__c> rows = new List<PMS_Booking__c>();
    for (Integer i = 0; i < 200; i++) {
      rows.add(booking(c.Id, 'Completed'));
    }
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    insert rows;
    Assert.areEqual(1, Limits.getQueueableJobs(), 'One job per save');
    Test.stopTest();
    Assert.areEqual(200, reload(c.Id).PMS_Total_Stays__c);
  }

  // ------------------------------------------------------------ parties

  @isTest
  static void partyInsertRecalculatesPartyContact() {
    arrange();
    Contact primary = guest('PartyPrimary');
    Contact member = guest('PartyMember');
    PMS_Booking__c b = insertBooking(primary.Id, 'Completed');
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = member.Id);
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Assert.areEqual(1, reload(member.Id).PMS_Total_Stays__c);
    assertNotRefreshed(primary.Id, 'Primary not part of a party event');
  }

  @isTest
  static void partyContactChangeRecalculatesOldAndNew() {
    arrange();
    Contact primary = guest('PcPrimary');
    Contact oldM = guest('PcOld');
    Contact newM = guest('PcNew');
    PMS_Booking__c b = insertBooking(primary.Id, 'Completed');
    PMS_Booking_Party__c p = new PMS_Booking_Party__c(
      Booking__c = b.Id,
      Contact__c = oldM.Id
    );
    insert p;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    p.Contact__c = newM.Id;
    update p;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Assert.areEqual(0, reload(oldM.Id).PMS_Total_Stays__c);
    Assert.areEqual(1, reload(newM.Id).PMS_Total_Stays__c);
  }

  @isTest
  static void partyUpdateWithoutContactChangeDoesNotEnqueue() {
    arrange();
    Contact primary = guest('PnPrimary');
    Contact m = guest('PnMember');
    PMS_Booking__c b = insertBooking(primary.Id, 'Completed');
    PMS_Booking_Party__c p = new PMS_Booking_Party__c(
      Booking__c = b.Id,
      Contact__c = m.Id
    );
    insert p;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    p.Role__c = 'Guest';
    update p;
    Assert.areEqual(0, Limits.getQueueableJobs());
    Test.stopTest();
  }

  @isTest
  static void partyDeleteRecalculatesPartyContact() {
    arrange();
    Contact primary = guest('PdPrimary');
    Contact m = guest('PdMember');
    PMS_Booking__c b = insertBooking(primary.Id, 'Completed');
    PMS_Booking_Party__c p = new PMS_Booking_Party__c(
      Booking__c = b.Id,
      Contact__c = m.Id
    );
    insert p;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    delete p;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Contact r = reload(m.Id);
    Assert.isNotNull(r.PMS_Stats_Refreshed__c);
    Assert.areEqual(0, r.PMS_Total_Stays__c);
  }

  @isTest
  static void partyUndeleteRecalculatesPartyContact() {
    arrange();
    Contact primary = guest('PuPrimary');
    Contact m = guest('PuMember');
    PMS_Booking__c b = insertBooking(primary.Id, 'Completed');
    PMS_Booking_Party__c p = new PMS_Booking_Party__c(
      Booking__c = b.Id,
      Contact__c = m.Id
    );
    insert p;
    delete p;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    undelete p;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Assert.areEqual(1, reload(m.Id).PMS_Total_Stays__c);
  }

  // ------------------------------------------------------------ charges

  @isTest
  static void chargeInsertResolvesPrimaryAndPartyContacts() {
    arrange();
    Contact primary = guest('ChPrimary');
    Contact member = guest('ChMember');
    PMS_Booking__c b = insertBooking(primary.Id, 'Completed');
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = member.Id);
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    insert charge(b.Id);
    Assert.areEqual(
      1,
      Limits.getQueueableJobs(),
      'One job; the booking recalc update does not re-enqueue'
    );
    Test.stopTest();
    assertRefreshed(primary.Id, 'Primary resolved from booking');
    assertRefreshed(member.Id, 'Party contact resolved from booking');
    Assert.areEqual(1, reload(primary.Id).PMS_Total_Stays__c);
  }

  @isTest
  static void chargeUpdateWatchedFieldEnqueues() {
    arrange();
    Contact c = guest('ChUpd');
    PMS_Booking__c b = insertBooking(c.Id, 'Completed');
    PMS_Charge__c ch = charge(b.Id);
    insert ch;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    ch.Unit_Price__c = 250;
    update ch;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    assertRefreshed(c.Id, 'Recalculated after price change');
  }

  @isTest
  static void chargeUpdateUnwatchedFieldDoesNotEnqueue() {
    arrange();
    Contact c = guest('ChUnw');
    PMS_Booking__c b = insertBooking(c.Id, 'Completed');
    PMS_Charge__c ch = charge(b.Id);
    insert ch;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    ch.Description__c = 'Note only';
    update ch;
    Assert.areEqual(0, Limits.getQueueableJobs());
    Test.stopTest();
    assertNotRefreshed(c.Id, 'Nothing queued');
  }

  @isTest
  static void chargeDeleteEnqueues() {
    arrange();
    Contact c = guest('ChDel');
    PMS_Booking__c b = insertBooking(c.Id, 'Completed');
    PMS_Charge__c ch = charge(b.Id);
    insert ch;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    delete ch;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    assertRefreshed(c.Id, 'Recalculated after delete');
  }

  // ------------------------------------------------------------ job

  @isTest
  static void jobChunksAtOneHundredContacts() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Account a = PMS_TestDataFactory.account('Chunk');
    List<Contact> rows = new List<Contact>();
    for (Integer i = 0; i < 150; i++) {
      rows.add(
        new Contact(
          AccountId = a.Id,
          LastName = 'Chunk' + i,
          Email = 'chunk' + i + '@example.com'
        )
      );
    }
    insert rows;
    Set<Id> ids = new Map<Id, Contact>(rows).keySet();
    Test.startTest();
    new PMS_GuestStatsQueueable(ids, null).execute(null);
    Test.stopTest();
    Assert.areEqual(100, PMS_GuestStatsQueueable.CHUNK_SIZE);
    Assert.areEqual(
      100,
      [
        SELECT COUNT()
        FROM Contact
        WHERE Id IN :ids AND PMS_Stats_Refreshed__c != NULL
      ],
      'First chunk only; chaining is suppressed in tests'
    );
  }

  @isTest
  static void jobWithNullInputsIsSafe() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Test.startTest();
    new PMS_GuestStatsQueueable(null, null).execute(null);
    Test.stopTest();
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Contact WHERE PMS_Stats_Refreshed__c != NULL]
    );
  }

  // ------------------------------------------------------------ guards

  @isTest
  static void batchContextSkipsWithoutError() {
    arrange();
    guest('BatchGuard');
    Test.startTest();
    PMS_GuestStatsHookTestBatch.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Database.executeBatch(new PMS_GuestStatsHookTestBatch());
    Test.stopTest();
    Assert.areEqual(
      0,
      PMS_GuestStatsHookTestBatch.jobsAfterHook,
      'No job enqueued from batch context'
    );
  }

  @isTest
  static void queueableLimitReachedSkipsWithoutError() {
    arrange();
    Contact c = guest('LimitGuard');
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++) {
      System.enqueueJob(new FillerJob());
    }
    Assert.areEqual(Limits.getLimitQueueableJobs(), Limits.getQueueableJobs());
    insertBooking(c.Id, 'Completed'); // must not throw
    Assert.areEqual(
      Limits.getLimitQueueableJobs(),
      Limits.getQueueableJobs(),
      'Nothing added past the limit'
    );
    Test.stopTest();
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Booking__c WHERE Primary_Contact__c = :c.Id],
      'The save itself succeeded'
    );
  }

  @isTest
  static void hookFailureDoesNotPropagate() {
    arrange();
    PMS_GuestStatsQueueable.enabledOverride = true;
    // a null element throws inside the hook; the hook must swallow it
    PMS_GuestStatsQueueable.onBookingSave(
      new List<PMS_Booking__c>{ null },
      null
    );
    PMS_GuestStatsQueueable.onBookingBeforeDelete(
      new List<PMS_Booking__c>{ null }
    );
    PMS_GuestStatsQueueable.onPartySave(
      new List<PMS_Booking_Party__c>{ null },
      null
    );
    PMS_GuestStatsQueueable.onPartyDelete(
      new List<PMS_Booking_Party__c>{ null }
    );
    PMS_GuestStatsQueueable.onCharges(new List<PMS_Charge__c>{ null }, null);
    Assert.areEqual(0, Limits.getQueueableJobs());
  }

  @isTest
  static void eachHookCallEnqueuesItsOwnJob() {
    arrange();
    Contact c = guest('Retry');
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    PMS_Booking__c b = insertBooking(c.Id, 'Confirmed'); // job 1 for c
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = c.Id); // job 2 for c
    Assert.areEqual(
      2,
      Limits.getQueueableJobs(),
      'No cross-call suppression: a rolled-back first attempt must not hide the retry'
    );
    Test.stopTest();
  }

  @isTest
  static void queueableContextSkipsWithoutError() {
    arrange();
    Contact c = guest('QCtx');
    hookContactId = c.Id;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    System.enqueueJob(new HookQueueable());
    Test.stopTest();
    Assert.areEqual(0, queueableJobs, 'No child job from a Queueable');
  }

  @isTest
  static void scheduledContextSkipsWithoutError() {
    arrange();
    Contact c = guest('SCtx');
    hookContactId = c.Id;
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    System.schedule(
      'PMS guest stats hook test',
      '0 0 0 1 1 ? 2099',
      new HookSchedulable()
    );
    Test.stopTest();
    // Statics set inside the scheduled execute don't carry back to the test, so check the job table instead.
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE
          JobType = 'Queueable'
          AND ApexClass.Name = 'PMS_GuestStatsQueueable'
      ],
      'No job from a Schedulable'
    );
  }

  @isTest
  static void bookingDeleteRecalculatesPartyContacts() {
    arrange();
    Contact primary = guest('BdPrimary');
    Contact member = guest('BdMember');
    PMS_Booking__c b = insertBooking(primary.Id, 'Completed');
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = member.Id);
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    delete b;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    assertRefreshed(primary.Id, 'Primary recalculated');
    assertRefreshed(member.Id, 'Party contact recalculated');
  }

  @isTest
  static void bookingDeleteToggleOffNoSoqlNoJob() {
    arrange();
    Contact c = guest('BdOff');
    PMS_Booking__c b = insertBooking(c.Id, 'Completed');
    Test.startTest();
    Integer q = Limits.getQueries();
    PMS_GuestStatsQueueable.onBookingBeforeDelete(
      new List<PMS_Booking__c>{ b }
    );
    Assert.areEqual(q, Limits.getQueries(), 'No SOQL while off');
    Assert.areEqual(0, Limits.getQueueableJobs());
    Test.stopTest();
  }

  // ------------------------------------------------------------ status fields

  @isTest
  static void recordFailuresIncrementsCountAndKeepsWatermark() {
    PMS_Guest_Stats_Run__c s = PMS_Guest_Stats_Run__c.getOrgDefaults();
    Datetime ok = Datetime.newInstance(2026, 1, 2, 3, 4, 5);
    s.Last_Success__c = ok;
    s.Last_Error_Count__c = 2;
    upsert s;
    Test.startTest();
    PMS_GuestStatsQueueable.recordFailures(3, 'boom');
    Test.stopTest();
    PMS_Guest_Stats_Run__c r = PMS_Guest_Stats_Run__c.getOrgDefaults();
    Assert.areEqual(5, r.Last_Error_Count__c);
    Assert.areEqual('Real-time: boom', r.Last_Error__c);
    Assert.areEqual(ok, r.Last_Success__c, 'Watermark untouched');
  }

  @isTest
  static void recordFailuresFromEmptyTruncatesAndKeepsMessageOnNull() {
    PMS_GuestStatsQueueable.recordFailures(1, 'x'.repeat(400));
    PMS_Guest_Stats_Run__c r = PMS_Guest_Stats_Run__c.getOrgDefaults();
    Assert.areEqual(1, r.Last_Error_Count__c);
    Assert.areEqual(255, r.Last_Error__c.length());
    Assert.isTrue(r.Last_Error__c.startsWith('Real-time: '));
    Assert.isNull(r.Last_Success__c);
    String msg = r.Last_Error__c;
    PMS_GuestStatsQueueable.recordFailures(2, null);
    r = PMS_Guest_Stats_Run__c.getOrgDefaults();
    Assert.areEqual(3, r.Last_Error_Count__c);
    Assert.areEqual(msg, r.Last_Error__c, 'Null message keeps the last one');
  }

  @isTest
  static void successfulJobLeavesStatusAlone() {
    arrange();
    Contact c = guest('OkJob');
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    insertBooking(c.Id, 'Completed');
    Test.stopTest();
    PMS_Guest_Stats_Run__c r = PMS_Guest_Stats_Run__c.getOrgDefaults();
    Assert.isTrue(r.Last_Error_Count__c == null || r.Last_Error_Count__c == 0);
    Assert.isNull(r.Last_Error__c);
  }

  @isTest
  static void duplicateIdsInOneSaveAreQueuedOnce() {
    arrange();
    Contact c = guest('DupOne');
    PMS_GuestStatsQueueable.enabledOverride = true;
    Test.startTest();
    List<PMS_Booking__c> rows = new List<PMS_Booking__c>();
    for (Integer i = 0; i < 5; i++) {
      rows.add(booking(c.Id, 'Completed'));
    }
    insert rows;
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();
    Assert.areEqual(5, reload(c.Id).PMS_Total_Stays__c);
  }
}
