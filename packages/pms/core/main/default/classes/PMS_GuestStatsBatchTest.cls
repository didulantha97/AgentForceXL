@isTest
private class PMS_GuestStatsBatchTest {
  private static Datetime at(Integer dayOffset) {
    return Datetime.newInstance(
      Date.today().addDays(dayOffset),
      Time.newInstance(12, 0, 0, 0)
    );
  }

  private static Contact guest(String lastName) {
    return PMS_TestDataFactory.contact(
      PMS_TestDataFactory.account('Acc ' + lastName).Id,
      lastName
    );
  }

  private static PMS_Booking__c booking(
    Id primary,
    String status,
    Integer startOffset,
    Integer endOffset
  ) {
    return new PMS_Booking__c(
      Primary_Contact__c = primary,
      Status__c = status,
      Start__c = at(startOffset),
      End__c = at(endOffset)
    );
  }

  private static Contact reload(Id id) {
    return [
      SELECT
        PMS_Total_Stays__c,
        PMS_Room_Revenue__c,
        PMS_Next_Arrival__c,
        PMS_Stats_Refreshed__c
      FROM Contact
      WHERE Id = :id
    ];
  }

  private static void stale(Contact c) {
    c.PMS_Total_Stays__c = 77;
    c.PMS_Room_Revenue__c = 999;
    update c;
  }

  private static void run(Boolean full, String phase) {
    Test.startTest();
    Database.executeBatch(
      new PMS_GuestStatsBatch(full, Datetime.now().addDays(-1), phase),
      200
    );
    Test.stopTest();
  }

  private static void runSince(Datetime since, String phase) {
    Test.startTest();
    Database.executeBatch(new PMS_GuestStatsBatch(false, since, phase), 200);
    Test.stopTest();
  }

  private static PMS_Guest_Stats_Run__c status() {
    return PMS_Guest_Stats_Run__c.getOrgDefaults();
  }

  private static void setLastSuccess(Datetime dt) {
    PMS_Guest_Stats_Run__c s = PMS_Guest_Stats_Run__c.getOrgDefaults();
    s.Last_Success__c = dt;
    upsert s;
  }

  private static Datetime wholeSeconds(Integer dayOffset) {
    return Datetime.newInstance(
      Date.today().addDays(dayOffset),
      Time.newInstance(3, 0, 0, 0)
    );
  }

  private static String query(Boolean full, String phase) {
    return new PMS_GuestStatsBatch(full, Datetime.now().addDays(-1), phase)
      .start(null)
      .getQuery();
  }

  @isTest
  static void nextPhaseChainsPerMode() {
    Assert.areEqual(100, PMS_GuestStatsBatch.SCOPE_SIZE);
    Assert.areEqual(
      PMS_GuestStatsBatch.PARTY,
      new PMS_GuestStatsBatch(true, null, PMS_GuestStatsBatch.PRIMARY)
        .nextPhase()
    );
    Assert.areEqual(
      PMS_GuestStatsBatch.STALE,
      new PMS_GuestStatsBatch(true, null, PMS_GuestStatsBatch.PARTY).nextPhase()
    );
    Assert.isNull(
      new PMS_GuestStatsBatch(true, null, PMS_GuestStatsBatch.STALE)
        .nextPhase(),
      'full backfill ends after STALE'
    );
    Assert.areEqual(
      PMS_GuestStatsBatch.PARTY,
      new PMS_GuestStatsBatch(false).nextPhase()
    );
    Assert.areEqual(
      PMS_GuestStatsBatch.CHARGE,
      new PMS_GuestStatsBatch(false, null, PMS_GuestStatsBatch.PARTY)
        .nextPhase()
    );
    Assert.areEqual(
      PMS_GuestStatsBatch.DEPARTURE,
      new PMS_GuestStatsBatch(false, null, PMS_GuestStatsBatch.CHARGE)
        .nextPhase()
    );
    Assert.areEqual(
      PMS_GuestStatsBatch.ARRIVAL,
      new PMS_GuestStatsBatch(false, null, PMS_GuestStatsBatch.DEPARTURE)
        .nextPhase()
    );
    Assert.isNull(
      new PMS_GuestStatsBatch(false, null, PMS_GuestStatsBatch.ARRIVAL)
        .nextPhase()
    );
  }

  @isTest
  static void nullArgumentsDefaultToPrimaryPhase() {
    PMS_GuestStatsBatch b = new PMS_GuestStatsBatch(null, null, null);
    Assert.areEqual(PMS_GuestStatsBatch.PARTY, b.nextPhase());
    Assert.isTrue(b.start(null).getQuery().contains('PMS_Booking__c'));
  }

  @isTest
  static void startSelectsQueryPerPhaseAndMode() {
    String fullPrimary = query(true, PMS_GuestStatsBatch.PRIMARY);
    Assert.isTrue(fullPrimary.contains('PMS_Booking__c'), fullPrimary);
    Assert.isFalse(fullPrimary.contains('LastModifiedDate'), fullPrimary);
    String nightlyPrimary = query(false, PMS_GuestStatsBatch.PRIMARY);
    Assert.isTrue(nightlyPrimary.contains('PMS_Booking__c'), nightlyPrimary);
    Assert.isTrue(nightlyPrimary.contains('LastModifiedDate'), nightlyPrimary);

    String fullParty = query(true, PMS_GuestStatsBatch.PARTY);
    Assert.isTrue(fullParty.contains('PMS_Booking_Party__c'), fullParty);
    Assert.isFalse(fullParty.contains('LastModifiedDate'), fullParty);
    String nightlyParty = query(false, PMS_GuestStatsBatch.PARTY);
    Assert.isTrue(nightlyParty.contains('PMS_Booking_Party__c'), nightlyParty);
    Assert.isTrue(nightlyParty.contains('LastModifiedDate'), nightlyParty);

    String charge = query(false, PMS_GuestStatsBatch.CHARGE);
    Assert.isTrue(charge.contains('PMS_Charge__c'), charge);
    Assert.isTrue(charge.contains('Primary_Contact__c'), charge);

    String stale = query(true, PMS_GuestStatsBatch.STALE);
    Assert.isTrue(stale.contains('PMS_Stats_Refreshed__c'), stale);

    String departure = query(false, PMS_GuestStatsBatch.DEPARTURE);
    Assert.isTrue(departure.contains('End__c'), departure);

    String arrival = query(false, PMS_GuestStatsBatch.ARRIVAL);
    Assert.isTrue(arrival.contains('PMS_Next_Arrival__c'), arrival);
  }

  @isTest
  static void primaryPhaseFullRefreshesLinkedContactsOnly() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact linked = guest('Linked');
    Contact unlinked = guest('Unlinked');
    insert booking(linked.Id, 'Completed', -4, -2);
    stale(linked);
    stale(unlinked);
    run(true, PMS_GuestStatsBatch.PRIMARY);
    Assert.areEqual(1, reload(linked.Id).PMS_Total_Stays__c);
    Assert.areEqual(0, reload(linked.Id).PMS_Room_Revenue__c);
    Assert.areEqual(77, reload(unlinked.Id).PMS_Total_Stays__c);
  }

  @isTest
  static void primaryPhaseNightlyPicksRecentlyModifiedBookings() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Recent');
    insert booking(c.Id, 'Completed', -4, -2);
    stale(c);
    run(false, PMS_GuestStatsBatch.PRIMARY);
    Assert.areEqual(1, reload(c.Id).PMS_Total_Stays__c);
  }

  @isTest
  static void primaryPhaseNightlySkipsOldBookings() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Old');
    insert booking(c.Id, 'Completed', -4, -2);
    stale(c);
    Test.startTest();
    Database.executeBatch(
      new PMS_GuestStatsBatch(
        false,
        Datetime.now().addDays(1), // cutoff in the future: nothing modified since
        PMS_GuestStatsBatch.PRIMARY
      ),
      200
    );
    Test.stopTest();
    Assert.areEqual(77, reload(c.Id).PMS_Total_Stays__c);
  }

  @isTest
  static void partyPhaseRefreshesPartyOnlyGuest() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact payer = guest('PartyPayer');
    Contact member = guest('PartyMember');
    PMS_Booking__c b = booking(payer.Id, 'Completed', -5, -2);
    insert b;
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = member.Id);
    stale(member);
    run(true, PMS_GuestStatsBatch.PARTY);
    Assert.areEqual(1, reload(member.Id).PMS_Total_Stays__c);
    Assert.isNotNull(reload(member.Id).PMS_Stats_Refreshed__c);
  }

  @isTest
  static void partyPhaseNightlyRefreshesPartyOnlyGuest() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact payer = guest('NightPayer');
    Contact member = guest('NightMember');
    PMS_Booking__c b = booking(payer.Id, 'Completed', -5, -2);
    insert b;
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = member.Id);
    stale(member);
    run(false, PMS_GuestStatsBatch.PARTY);
    Assert.areEqual(1, reload(member.Id).PMS_Total_Stays__c);
  }

  @isTest
  static void chargePhaseRefreshesPrimaryContactRevenue() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Charged');
    PMS_Booking__c b = booking(c.Id, 'Completed', -4, -2);
    insert b;
    insert new PMS_Charge__c(
      Booking__c = b.Id,
      Charge_Type__c = 'Room Night',
      Quantity__c = 2,
      Unit_Price__c = 500,
      Status__c = 'Pending'
    );
    PMS_Booking__c cancelled = booking(c.Id, 'Cancelled', 8, 10);
    insert cancelled;
    insert new PMS_Charge__c(
      Booking__c = cancelled.Id,
      Charge_Type__c = 'Room Night',
      Quantity__c = 1,
      Unit_Price__c = 100,
      Status__c = 'Pending'
    );
    stale(c);
    run(false, PMS_GuestStatsBatch.CHARGE);
    Contact r = reload(c.Id);
    Assert.areEqual(1100, r.PMS_Room_Revenue__c, 'cancellation fee counts');
    Assert.areEqual(1, r.PMS_Total_Stays__c);
  }

  @isTest
  static void arrivalPhasePicksUpPastDueNextArrival() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact due = guest('Due');
    Contact dueToday = guest('DueToday');
    Contact future = guest('FutureArrival');
    Contact none = guest('NoArrival');
    insert booking(due.Id, 'Completed', -4, -2); // arrival already happened
    due.PMS_Next_Arrival__c = Date.today().addDays(-4);
    dueToday.PMS_Next_Arrival__c = Date.today();
    future.PMS_Next_Arrival__c = Date.today().addDays(3);
    future.PMS_Total_Stays__c = 77;
    none.PMS_Total_Stays__c = 77;
    update new List<Contact>{ due, dueToday, future, none };
    run(false, PMS_GuestStatsBatch.ARRIVAL);
    Contact r = reload(due.Id);
    Assert.areEqual(1, r.PMS_Total_Stays__c);
    Assert.isNull(r.PMS_Next_Arrival__c, 'stale arrival cleared');
    Assert.isNull(reload(dueToday.Id).PMS_Next_Arrival__c);
    Assert.areEqual(0, reload(dueToday.Id).PMS_Total_Stays__c);
    Assert.areEqual(77, reload(future.Id).PMS_Total_Stays__c);
    Assert.areEqual(77, reload(none.Id).PMS_Total_Stays__c);
  }

  @isTest
  static void stalePhaseResetsContactWhoseBookingsWereDeleted() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Orphan');
    Contact never = guest('NeverComputed');
    PMS_Booking__c b = booking(c.Id, 'Completed', -4, -2);
    insert b;
    PMS_GuestStatsService.recalc(new Set<Id>{ c.Id });
    Assert.areEqual(1, reload(c.Id).PMS_Total_Stays__c);
    delete b;
    never.PMS_Total_Stays__c = 77;
    update never;
    run(true, PMS_GuestStatsBatch.STALE);
    Contact r = reload(c.Id);
    Assert.areEqual(0, r.PMS_Total_Stays__c, 'stale stats reset');
    Assert.areEqual(0, r.PMS_Room_Revenue__c);
    Assert.areEqual(
      77,
      reload(never.Id).PMS_Total_Stays__c,
      'contacts without stats are not in STALE scope'
    );
  }

  @isTest
  static void departurePhaseRecalcsPrimaryAndPartyContacts() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact payer = guest('DepPayer');
    Contact member = guest('DepMember');
    Contact todayGuest = guest('DepToday');
    Contact oldGuest = guest('DepOld');
    PMS_Booking__c b = booking(payer.Id, 'Completed', -4, -1);
    PMS_Booking__c bToday = booking(todayGuest.Id, 'Active', -2, 0);
    PMS_Booking__c bOld = booking(oldGuest.Id, 'Completed', -30, -20);
    insert new List<PMS_Booking__c>{ b, bToday, bOld };
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = member.Id);
    stale(payer);
    stale(member);
    stale(todayGuest);
    stale(oldGuest);
    runSince(Datetime.now().addDays(-3), PMS_GuestStatsBatch.DEPARTURE);
    Assert.areEqual(1, reload(payer.Id).PMS_Total_Stays__c, 'primary');
    Assert.areEqual(1, reload(member.Id).PMS_Total_Stays__c, 'party member');
    Assert.areEqual(
      77,
      reload(todayGuest.Id).PMS_Total_Stays__c,
      'departing today not selected'
    );
    Assert.areEqual(
      77,
      reload(oldGuest.Id).PMS_Total_Stays__c,
      'departed before cutoff not selected'
    );
  }

  @isTest
  static void successfulRunAdvancesLastSuccessAndWritesStatus() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Datetime runStart = wholeSeconds(-1);
    setLastSuccess(wholeSeconds(-5));
    Test.startTest();
    Database.executeBatch(
      new PMS_GuestStatsBatch(
        true,
        null,
        PMS_GuestStatsBatch.STALE,
        runStart,
        0,
        null
      ),
      100
    );
    Test.stopTest();
    PMS_Guest_Stats_Run__c s = status();
    Assert.areEqual(runStart, s.Last_Success__c);
    Assert.areEqual(0, s.Last_Error_Count__c);
    Assert.isNull(s.Last_Error__c);
    Assert.isNotNull(s.Last_Run__c);
  }

  @isTest
  static void failedRecalcLeavesLastSuccessAndRecordsError() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Datetime previous = wholeSeconds(-5);
    setLastSuccess(previous);
    Contact gone = guest('GoneBatch');
    delete gone; // cannot be saved: per-record failure reported by the service
    PMS_GuestStatsBatch b = new PMS_GuestStatsBatch(
      true,
      null,
      PMS_GuestStatsBatch.STALE,
      wholeSeconds(-1),
      0,
      null
    );
    Test.startTest();
    b.execute(null, new List<SObject>{ new Contact(Id = gone.Id) });
    b.finish(null);
    Test.stopTest();
    PMS_Guest_Stats_Run__c s = status();
    Assert.areEqual(previous, s.Last_Success__c, 'watermark not advanced');
    Assert.areEqual(1, s.Last_Error_Count__c);
    Assert.isNotNull(s.Last_Error__c);
    Assert.isTrue(s.Last_Error__c.contains(String.valueOf(gone.Id)));
    Assert.isNotNull(s.Last_Run__c);
  }

  @isTest
  static void carriedErrorsKeepFirstMessageAndBlockWatermark() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Datetime previous = wholeSeconds(-5);
    setLastSuccess(previous);
    String longMsg = 'earlier failure ' + 'x'.repeat(300);
    PMS_GuestStatsBatch b = new PMS_GuestStatsBatch(
      false,
      null,
      PMS_GuestStatsBatch.ARRIVAL,
      wholeSeconds(-1),
      2,
      longMsg
    );
    b.finish(null);
    PMS_Guest_Stats_Run__c s = status();
    Assert.areEqual(previous, s.Last_Success__c);
    Assert.areEqual(2, s.Last_Error_Count__c);
    Assert.areEqual(255, s.Last_Error__c.length(), 'message truncated');
    Assert.isTrue(s.Last_Error__c.startsWith('earlier failure'));
  }

  @isTest
  static void nonFinalPhaseDoesNotWriteStatus() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    run(false, PMS_GuestStatsBatch.PRIMARY);
    Assert.isNull(status().Last_Run__c, 'status written only after last phase');
  }

  @isTest
  static void nightlyCutoffInFutureSkipsOlderBookings() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('CutoffFuture');
    insert booking(c.Id, 'Completed', -4, -2);
    stale(c);
    setLastSuccess(Datetime.now().addDays(1)); // nothing modified since
    Test.startTest();
    Database.executeBatch(new PMS_GuestStatsBatch(false), 200);
    Test.stopTest();
    Assert.areEqual(77, reload(c.Id).PMS_Total_Stays__c, 'before watermark');
  }

  @isTest
  static void nightlyCutoffInPastPicksUpModifiedBookings() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('CutoffPast');
    insert booking(c.Id, 'Completed', -4, -2);
    stale(c);
    setLastSuccess(Datetime.now().addDays(-1));
    Test.startTest();
    Database.executeBatch(new PMS_GuestStatsBatch(false), 200);
    Test.stopTest();
    Assert.areEqual(1, reload(c.Id).PMS_Total_Stays__c, 'after watermark');
  }

  @isTest
  static void nightlyCutoffFallsBackTo25HoursWithoutStatus() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Fallback');
    insert booking(c.Id, 'Completed', -4, -2);
    stale(c);
    Assert.isNull(status().Last_Success__c);
    Test.startTest();
    Database.executeBatch(new PMS_GuestStatsBatch(false), 200);
    Test.stopTest();
    Assert.areEqual(1, reload(c.Id).PMS_Total_Stays__c);
  }

  @isTest
  static void bulk200ContactsRefreshedAcrossTwoChunks() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Account a = PMS_TestDataFactory.account('Bulk Batch Co');
    List<Contact> contacts = new List<Contact>();
    for (Integer i = 0; i < 200; i++) {
      contacts.add(new Contact(AccountId = a.Id, LastName = 'BB' + i));
    }
    insert contacts;
    List<PMS_Booking__c> bookings = new List<PMS_Booking__c>();
    for (Contact c : contacts) {
      bookings.add(booking(c.Id, 'Completed', -4, -2));
    }
    insert bookings;
    PMS_GuestStatsBatch b = new PMS_GuestStatsBatch(
      true,
      null,
      PMS_GuestStatsBatch.PRIMARY
    );
    Test.startTest();
    for (Integer chunk = 0; chunk < 2; chunk++) {
      List<SObject> scope = new List<SObject>();
      for (Integer i = 0; i < PMS_GuestStatsBatch.SCOPE_SIZE; i++) {
        scope.add(new Contact(Id = contacts[chunk * 100 + i].Id));
      }
      b.execute(null, scope);
    }
    Test.stopTest();
    Integer ok = 0;
    for (Contact c : [
      SELECT PMS_Total_Stays__c
      FROM Contact
      WHERE Id IN :contacts
    ]) {
      if (c.PMS_Total_Stays__c == 1) {
        ok++;
      }
    }
    Assert.areEqual(200, ok);
  }

  @isTest
  static void dailyJobStillRunsAndRefreshesStats() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Daily');
    insert booking(c.Id, 'Completed', -4, -2);
    stale(c);
    Test.startTest();
    new PMS_DailyJob().execute(null);
    Test.stopTest();
    Assert.areEqual(1, reload(c.Id).PMS_Total_Stays__c);
  }
}
