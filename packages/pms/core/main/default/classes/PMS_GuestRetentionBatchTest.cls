@isTest
private class PMS_GuestRetentionBatchTest {
  private static Datetime at(Integer dayOffset) {
    return Datetime.newInstance(
      Date.today().addDays(dayOffset),
      Time.newInstance(12, 0, 0, 0)
    );
  }

  private static void settings(Decimal months, String mode) {
    PMS_Settings__c s = PMS_Settings__c.getOrgDefaults();
    s.put('Guest_Retention_Months__c', months);
    s.put('Guest_Retention_Mode__c', mode);
    upsert s;
  }

  private static Account acct(String name, String role) {
    Account a = new Account(
      Name = name,
      PMS_Party_Role__c = role,
      PMS_Customer_Type__c = 'Consumer'
    );
    insert a;
    return a;
  }

  /** Contact created long ago (default 40 months) so only its stays can keep it inside the retention window. */
  private static Contact oldContact(
    String last,
    String role,
    Integer ageMonths
  ) {
    Contact c = new Contact(
      AccountId = acct('Acc ' + last, role).Id,
      FirstName = 'Old',
      LastName = last,
      Email = last.toLowerCase() + '@example.com'
    );
    insert c;
    Test.setCreatedDate(c.Id, Datetime.now().addMonths(-ageMonths));
    return c;
  }

  private static PMS_Booking__c booking(
    Id primary,
    String status,
    Integer startOffset,
    Integer endOffset
  ) {
    PMS_Booking__c b = new PMS_Booking__c(
      Primary_Contact__c = primary,
      Status__c = status,
      Start__c = at(startOffset),
      End__c = at(endOffset),
      Total_Amount__c = 0,
      Amount_Paid__c = 0
    );
    insert b;
    return b;
  }

  private static Contact reload(Id id) {
    return [
      SELECT FirstName, LastName, Email, PMS_Anonymised__c, PMS_Retention_Due__c
      FROM Contact
      WHERE Id = :id
    ];
  }

  private static void runBatch() {
    Test.startTest();
    Database.executeBatch(new PMS_GuestRetentionBatch(), 200);
    Test.stopTest();
  }

  // ---------------------------------------------------------------- settings

  @isTest
  static void defaultsWhenSettingsBlank() {
    Assert.areEqual(36, PMS_GuestRetentionBatch.retentionMonths());
    Assert.areEqual('FLAG', PMS_GuestRetentionBatch.mode());
    upsert PMS_Settings__c.getOrgDefaults();
    Assert.areEqual(36, PMS_GuestRetentionBatch.retentionMonths());
    Assert.areEqual('FLAG', PMS_GuestRetentionBatch.mode());
  }

  @isTest
  static void settingsAreHonouredAndInvalidValuesFallBack() {
    settings(12, 'ANONYMISE');
    Assert.areEqual(12, PMS_GuestRetentionBatch.retentionMonths());
    Assert.areEqual('ANONYMISE', PMS_GuestRetentionBatch.mode());
    settings(0, ' anonymise ');
    Assert.areEqual(
      36,
      PMS_GuestRetentionBatch.retentionMonths(),
      'months < 1 falls back'
    );
    Assert.areEqual(
      'ANONYMISE',
      PMS_GuestRetentionBatch.mode(),
      'trim and case-insensitive'
    );
    settings(6, 'DELETE');
    Assert.areEqual(
      'FLAG',
      PMS_GuestRetentionBatch.mode(),
      'unknown mode is FLAG'
    );
    Assert.areEqual(6, PMS_GuestRetentionBatch.retentionMonths());
  }

  // ---------------------------------------------------------------- FLAG mode

  @isTest
  static void flagModeSetsRetentionDueOnlyAndExercisesBothSemiJoins() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    // defaults: 36 months, FLAG
    Contact stale = oldContact('Stale', 'Guest', 40);
    booking(stale.Id, 'Completed', -1300, -1298); // ended ~43 months ago: outside window

    Contact recentPrimary = oldContact('RecentPrimary', 'Guest', 40);
    booking(recentPrimary.Id, 'Completed', -12, -10); // primary semi-join

    Contact lead = oldContact('LeadX', null, 40);
    Contact recentParty = oldContact('RecentParty', 'Guest', 40);
    PMS_Booking__c shared = booking(lead.Id, 'Completed', -20, -18);
    insert new PMS_Booking_Party__c(
      Booking__c = shared.Id,
      Contact__c = recentParty.Id
    ); // party semi-join with Booking__r.End__c

    Contact stalePartyOnly = oldContact('StaleParty', 'Guest', 40);
    PMS_Booking__c oldShared = booking(lead.Id, 'Completed', -1400, -1398);
    insert new PMS_Booking_Party__c(
      Booking__c = oldShared.Id,
      Contact__c = stalePartyOnly.Id
    );

    Contact noBooking = oldContact('NoBooking', 'Guest', 40); // measured from CreatedDate
    Contact newGuest = oldContact('NewGuest', 'Guest', 2); // created 2 months ago

    // multi-value role: INCLUDES must match
    Contact multi = oldContact('Multi', 'Guest;Owner', 40);

    runBatch();

    Assert.areEqual(Date.today(), reload(stale.Id).PMS_Retention_Due__c);
    Assert.areEqual(
      Date.today(),
      reload(stalePartyOnly.Id).PMS_Retention_Due__c
    );
    Assert.areEqual(Date.today(), reload(noBooking.Id).PMS_Retention_Due__c);
    Assert.areEqual(
      Date.today(),
      reload(multi.Id).PMS_Retention_Due__c,
      'INCLUDES matches multi-select role'
    );
    Assert.isNull(
      reload(recentPrimary.Id).PMS_Retention_Due__c,
      'recent primary stay'
    );
    Assert.isNull(
      reload(recentParty.Id).PMS_Retention_Due__c,
      'recent party stay'
    );
    Assert.isNull(
      reload(newGuest.Id).PMS_Retention_Due__c,
      'created inside the window'
    );
    Assert.isNull(
      reload(lead.Id).PMS_Retention_Due__c,
      'staff account is not a guest'
    );
    // FLAG only: nothing anonymised or changed
    for (
      Id id : new List<Id>{
        stale.Id,
        stalePartyOnly.Id,
        noBooking.Id,
        multi.Id
      }
    ) {
      Contact c = reload(id);
      Assert.isFalse(c.PMS_Anonymised__c);
      Assert.isNotNull(c.Email);
    }
  }

  @isTest
  static void flagModeDoesNotReflagAlreadyFlaggedGuests() {
    Contact c = oldContact('Flagged', 'Guest', 40);
    Date earlier = Date.today().addDays(-20);
    update new Contact(Id = c.Id, PMS_Retention_Due__c = earlier);
    runBatch();
    Assert.areEqual(earlier, reload(c.Id).PMS_Retention_Due__c);
  }

  @isTest
  static void excludesStaffVendorOwnerAndAnonymisedContacts() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact vendor = oldContact('Vendor1', 'Vendor', 40);
    Contact owner = oldContact('Owner1', 'Owner', 40);
    Contact staff = oldContact('Staff1', null, 40);
    Contact done = oldContact('Done1', 'Guest', 40);
    update new Contact(Id = done.Id, PMS_Anonymised__c = true);
    Contact guest = oldContact('Guest1', 'Guest', 40);
    runBatch();
    Assert.isNull(reload(vendor.Id).PMS_Retention_Due__c);
    Assert.isNull(reload(owner.Id).PMS_Retention_Due__c);
    Assert.isNull(reload(staff.Id).PMS_Retention_Due__c);
    Assert.isNull(reload(done.Id).PMS_Retention_Due__c);
    Assert.areEqual(Date.today(), reload(guest.Id).PMS_Retention_Due__c);
  }

  @isTest
  static void contactWithStayStatsIsConsideredEvenWithoutGuestRole() {
    Contact c = oldContact('Stats1', null, 40);
    update new Contact(Id = c.Id, PMS_Total_Stays__c = 2);
    runBatch();
    Assert.areEqual(Date.today(), reload(c.Id).PMS_Retention_Due__c);
  }

  @isTest
  static void customRetentionMonthsMovesTheCutoff() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    settings(6, 'FLAG');
    Contact c = oldContact('SixMonths', 'Guest', 20);
    booking(c.Id, 'Completed', -300, -298); // ~10 months ago: older than 6 months
    Contact recent = oldContact('ThreeMonths', 'Guest', 20);
    booking(recent.Id, 'Completed', -92, -90); // ~3 months ago
    runBatch();
    Assert.areEqual(Date.today(), reload(c.Id).PMS_Retention_Due__c);
    Assert.isNull(reload(recent.Id).PMS_Retention_Due__c);
  }

  // ---------------------------------------------------------------- ANONYMISE mode

  @isTest
  static void anonymiseModeAnonymisesCleanAndFlagsBlocked() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    settings(36, 'ANONYMISE');
    Contact clean = oldContact('CleanOld', 'Guest', 40);
    booking(clean.Id, 'Completed', -1300, -1298);

    // blocked: old stay but an unpaid balance (not inside the retention window, so still selected)
    Contact blocked = oldContact('BlockedOld', 'Guest', 40);
    PMS_Booking__c bb = booking(blocked.Id, 'Completed', -1300, -1298);
    update new PMS_Booking__c(
      Id = bb.Id,
      Total_Amount__c = 80,
      Amount_Paid__c = 0
    );
    Assert.areEqual(
      80,
      [SELECT Balance_Due__c FROM PMS_Booking__c WHERE Id = :bb.Id]
      .Balance_Due__c,
      'precondition'
    );

    Contact recent = oldContact('RecentKeep', 'Guest', 40);
    booking(recent.Id, 'Completed', -30, -28);

    runBatch();

    Contact c = reload(clean.Id);
    Assert.isTrue(c.PMS_Anonymised__c);
    Assert.isNull(c.Email);
    Assert.areNotEqual('Old', c.FirstName, 'first name cleared');
    Assert.areEqual('Guest', c.LastName);
    Assert.isNull(c.PMS_Retention_Due__c);
    Assert.isTrue(
      [SELECT PMS_Anonymisation_Reason__c FROM Contact WHERE Id = :clean.Id]
        .PMS_Anonymisation_Reason__c.startsWith(
          'Retention policy: no activity for 36 months'
        )
    );

    Contact b = reload(blocked.Id);
    Assert.isFalse(b.PMS_Anonymised__c);
    Assert.areEqual('BlockedOld', b.LastName);
    Assert.areEqual('Old', b.FirstName, 'PII untouched for blocked guest');
    Assert.areEqual('blockedold@example.com', b.Email);
    Assert.areEqual(
      Date.today(),
      b.PMS_Retention_Due__c,
      'blocked guest flagged for review'
    );

    Contact r = reload(recent.Id);
    Assert.isFalse(r.PMS_Anonymised__c);
    Assert.isNull(r.PMS_Retention_Due__c);
  }

  @isTest
  static void anonymiseModeRunsWithoutUserPermission() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    settings(36, 'ANONYMISE');
    PMS_GuestErasureService.permissionOverride = false; // the batch uses the trusted path
    Contact c = oldContact('NoPermJob', 'Guest', 40);
    runBatch();
    Assert.isTrue(reload(c.Id).PMS_Anonymised__c);
  }

  @isTest
  static void failedChunkIsRetriedPerGuestAndFlagged() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    settings(36, 'ANONYMISE');
    Contact c = oldContact('Failing', 'Guest', 40);
    booking(c.Id, 'Completed', -1300, -1298);
    Contact c2 = oldContact('Failing2', 'Guest', 40);
    booking(c2.Id, 'Completed', -1300, -1298);
    // suspended licence: booking updates are rejected, so the service rolls back and the batch flags for review
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    Test.startTest();
    Database.executeBatch(new PMS_GuestRetentionBatch(), 200);
    Test.stopTest();
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    for (Id id : new List<Id>{ c.Id, c2.Id }) {
      Contact r = reload(id);
      Assert.isFalse(r.PMS_Anonymised__c, 'rolled back');
      Assert.areEqual('Failing', r.LastName.left(7));
      Assert.areEqual(
        Date.today(),
        r.PMS_Retention_Due__c,
        'failed guests are flagged for a person'
      );
    }
  }

  // ---------------------------------------------------------------- bulk + scheduling

  @isTest
  static void bulkTwoHundredGuestsInFlagMode() {
    List<Account> accs = new List<Account>();
    for (Integer i = 0; i < 200; i++) {
      accs.add(
        new Account(
          Name = 'BulkAcc ' + i,
          PMS_Party_Role__c = 'Guest',
          PMS_Customer_Type__c = 'Consumer'
        )
      );
    }
    insert accs;
    List<Contact> cs = new List<Contact>();
    for (Integer i = 0; i < 200; i++) {
      cs.add(new Contact(AccountId = accs[i].Id, LastName = 'Bulk' + i));
    }
    insert cs;
    for (Contact c : cs) {
      Test.setCreatedDate(c.Id, Datetime.now().addMonths(-40));
    }
    runBatch();
    Assert.areEqual(
      200,
      [
        SELECT COUNT()
        FROM Contact
        WHERE LastName LIKE 'Bulk%' AND PMS_Retention_Due__c = :Date.today()
      ]
    );
  }

  @isTest
  static void scopeSizeConstantIsSane() {
    Assert.areEqual(10, PMS_GuestRetentionBatch.SCOPE_SIZE);
    Assert.areEqual(36, PMS_GuestRetentionBatch.DEFAULT_MONTHS);
  }
}
