@isTest
private class PMS_Guest360ControllerTest {
  // ---------- data helpers ----------
  private static Contact guest(String lastName) {
    return PMS_TestDataFactory.contact(
      PMS_TestDataFactory.account('Acc ' + lastName).Id,
      lastName
    );
  }

  /** Noon on today + offset so date conversions are stable across time zones. */
  private static Datetime at(Integer dayOffset) {
    return Datetime.newInstance(
      Date.today().addDays(dayOffset),
      Time.newInstance(12, 0, 0, 0)
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

  private static PMS_Booking__c money(
    PMS_Booking__c b,
    Decimal total,
    Decimal paid
  ) {
    b.Total_Amount__c = total;
    b.Amount_Paid__c = paid;
    return b;
  }

  private static PMS_Guest_Preference__c pref(
    Id contactId,
    String category,
    String value,
    Date captured,
    Boolean active
  ) {
    return new PMS_Guest_Preference__c(
      Contact__c = contactId,
      Category__c = category,
      Value__c = value,
      Source__c = 'Staff',
      Captured_On__c = captured,
      Active__c = active
    );
  }

  private static Case kase(
    Id contactId,
    Id bookingId,
    String status,
    String subject
  ) {
    return new Case(
      ContactId = contactId,
      PMS_Booking__c = bookingId,
      Status = status,
      Subject = subject,
      Origin = 'Phone'
    );
  }

  private static Set<Id> stayIds(List<PMS_Guest360Controller.Stay> stays) {
    Set<Id> ids = new Set<Id>();
    for (PMS_Guest360Controller.Stay s : stays) {
      ids.add(s.bookingId);
    }
    return ids;
  }

  private static void assertGeneric(Id id, Boolean card) {
    Boolean thrown = false;
    try {
      if (card) {
        PMS_Guest360Controller.getGuestCard(id);
      } else {
        PMS_Guest360Controller.getGuest360(id);
      }
    } catch (AuraHandledException e) {
      thrown = true;
      if (e.getMessage() != null && id != null) {
        Assert.isFalse(
          e.getMessage().contains(String.valueOf(id)),
          'message must not leak the record id'
        );
      }
    }
    Assert.isTrue(thrown, 'AuraHandledException expected');
  }

  // ---------- user / permission helpers ----------
  private static Boolean includePartyAccess = true;

  private static Id profileId(String name) {
    List<Profile> ps = [SELECT Id FROM Profile WHERE Name = :name LIMIT 1];
    return ps.isEmpty() ? null : ps[0].Id;
  }

  private static User makeUser(String alias, Id profId) {
    User u = new User(
      Alias = alias,
      Email = alias + '@pms-g360.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'G360 ' + alias,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profId,
      TimeZoneSidKey = 'GMT',
      Username = alias + '.' + Crypto.getRandomInteger() + '@pms-g360.test'
    );
    // Setup DML in runAs block avoids MIXED_DML_OPERATION with earlier data inserts.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
    }
    return u;
  }

  /**
   * Base read access to the PMS objects the controller touches, via a test-created permission set.
   * withBalance=false leaves out FLS on PMS_Booking__c.Balance_Due__c.
   */
  private static void grantPmsRead(
    Id userId,
    Boolean withViewer,
    Boolean withBalance
  ) {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      PermissionSet ps = new PermissionSet(
        Name = 'G360_Test_' + String.valueOf(userId),
        Label = 'G360 Test ' + String.valueOf(userId)
      );
      insert ps;
      List<ObjectPermissions> ops = new List<ObjectPermissions>();
      for (
        String o : new List<String>{
          'PMS_Booking__c',
          'PMS_Intake_Form__c',
          'PMS_Site__c', // PMS_Space__c is master-detail to Site: Read on Space requires Read on Site
          'PMS_Space__c',
          'Case'
        }
      ) {
        ops.add(
          new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = o,
            PermissionsRead = true
          )
        );
      }
      if (includePartyAccess) {
        ops.add(
          new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'PMS_Booking_Party__c',
            PermissionsRead = true
          )
        );
      }
      insert ops;
      List<String> fields = new List<String>{
        'PMS_Booking__c.Primary_Contact__c',
        'PMS_Booking__c.Start__c',
        'PMS_Booking__c.End__c',
        'PMS_Booking__c.Status__c',
        'PMS_Booking__c.Channel__c',
        'PMS_Booking__c.Total_Amount__c',
        'PMS_Booking__c.Amount_Paid__c',
        'PMS_Booking__c.Special_Requests__c',
        'PMS_Intake_Form__c.Consent_Given__c',
        'PMS_Intake_Form__c.Form_Type__c',
        'Case.PMS_Booking__c'
      };
      if (withBalance) {
        fields.add('PMS_Booking__c.Balance_Due__c');
      }
      List<FieldPermissions> fps = new List<FieldPermissions>();
      for (String f : fields) {
        fps.add(
          new FieldPermissions(
            ParentId = ps.Id,
            SobjectType = f.substringBefore('.'),
            Field = f,
            PermissionsRead = true,
            PermissionsEdit = false
          )
        );
      }
      insert fps;
      List<PermissionSetAssignment> asg = new List<PermissionSetAssignment>{
        new PermissionSetAssignment(
          AssigneeId = userId,
          PermissionSetId = ps.Id
        )
      };
      if (withViewer) {
        List<PermissionSet> v = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'PMS_Guest360_Viewer'
          LIMIT 1
        ];
        Assert.isFalse(v.isEmpty(), 'PMS_Guest360_Viewer must exist');
        asg.add(
          new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = v[0].Id
          )
        );
      }
      insert asg;
    }
  }

  /** Full dataset for a contact owned by ownerId (so private OWD does not hide it). */
  private static Contact scenario(Id ownerId) {
    Account a = new Account(Name = 'Scenario Acc', OwnerId = ownerId);
    insert a;
    Contact c = new Contact(
      AccountId = a.Id,
      LastName = 'Scenario',
      Email = 'scenario@example.com',
      OwnerId = ownerId,
      PMS_VIP_Level__c = 'VIP 1',
      PMS_Total_Stays__c = 3,
      PMS_Marketing_Consent__c = true
    );
    insert c;
    List<PMS_Booking__c> bs = new List<PMS_Booking__c>{
      money(booking(c.Id, 'Confirmed', 5, 7), 500, 100),
      money(booking(c.Id, 'Cancelled', 9, 10), 300, 0),
      money(booking(c.Id, 'Completed', -5, -3), 1000, 0)
    };
    insert bs;
    insert pref(c.Id, 'Room', 'High floor', Date.today(), true);
    Case cs = kase(c.Id, null, 'New', 'Scenario case');
    cs.OwnerId = ownerId;
    insert cs;
    PMS_Intake_Form__c f = new PMS_Intake_Form__c(
      Contact__c = c.Id,
      Form_Type__c = 'GDPR Consent',
      Consent_Given__c = true
    );
    insert f;
    return c;
  }

  // ---------- happy path ----------
  @isTest
  static void staysViaPrimaryPartyAndBothAreDeduplicated() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Stays');
    Contact other = guest('OtherPayer');
    PMS_Booking__c primaryOnly = money(
      booking(c.Id, 'Confirmed', 5, 7),
      500,
      100
    );
    primaryOnly.Channel__c = 'Direct';
    primaryOnly.Special_Requests__c = 'Late arrival';
    PMS_Booking__c partyOnly = money(
      booking(other.Id, 'Confirmed', 2, 4),
      700,
      0
    );
    partyOnly.Special_Requests__c = 'Private';
    PMS_Booking__c both = booking(c.Id, 'Confirmed', 10, 12);
    PMS_Booking__c inHouse = booking(c.Id, 'Active', -1, 1);
    PMS_Booking__c endsToday = booking(c.Id, 'Active', -2, 0);
    PMS_Booking__c past = booking(c.Id, 'Completed', -5, -3);
    PMS_Booking__c unrelated = booking(other.Id, 'Confirmed', 3, 4);
    insert new List<PMS_Booking__c>{
      primaryOnly,
      partyOnly,
      both,
      inHouse,
      endsToday,
      past,
      unrelated
    };
    insert new List<PMS_Booking_Party__c>{
      new PMS_Booking_Party__c(Booking__c = partyOnly.Id, Contact__c = c.Id),
      new PMS_Booking_Party__c(Booking__c = both.Id, Contact__c = c.Id)
    };
    Test.startTest();
    PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
      c.Id
    );
    Test.stopTest();

    Assert.isTrue(g.upcomingStays.accessible);
    Assert.isTrue(g.pastStays.accessible);
    List<PMS_Guest360Controller.Stay> up = g.upcomingStays.items;
    Assert.areEqual(
      5,
      up.size(),
      'in-house, ends-today, party, primary, both (once)'
    );
    Assert.areEqual(5, stayIds(up).size(), 'no duplicate stays');
    Assert.isFalse(stayIds(up).contains(unrelated.Id));
    Assert.isFalse(stayIds(up).contains(past.Id));
    // ascending by start
    Assert.areEqual(endsToday.Id, up[0].bookingId);
    Assert.areEqual(inHouse.Id, up[1].bookingId);
    Assert.areEqual(partyOnly.Id, up[2].bookingId);
    Assert.areEqual(primaryOnly.Id, up[3].bookingId);
    Assert.areEqual(both.Id, up[4].bookingId);
    PMS_Guest360Controller.Stay s = up[3];
    Assert.areEqual(Date.today().addDays(5), s.startDate);
    Assert.areEqual(Date.today().addDays(7), s.endDate);
    Assert.areEqual('Confirmed', s.status);
    Assert.areEqual('Direct', s.channel);
    Assert.areEqual(500, s.totalAmount);
    Assert.areEqual(400, s.balanceDue);
    Assert.areEqual('Late arrival', s.specialRequests);
    Assert.isFalse(s.viaParty);
    PMS_Guest360Controller.Stay ps = up[2];
    Assert.areEqual(partyOnly.Id, ps.bookingId);
    Assert.isTrue(ps.viaParty);
    Assert.isNull(ps.totalAmount);
    Assert.isNull(ps.balanceDue);
    Assert.isNull(ps.specialRequests);
    Assert.isNotNull(s.name);
    Assert.isNull(s.spaceName);

    Assert.areEqual(1, g.pastStays.items.size());
    Assert.areEqual(past.Id, g.pastStays.items[0].bookingId);
  }

  @isTest
  static void upcomingPastAndCaseListsAreCapped() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Caps');
    List<PMS_Booking__c> bs = new List<PMS_Booking__c>();
    for (Integer i = 1; i <= 7; i++) {
      bs.add(booking(c.Id, 'Confirmed', i, i + 1));
    }
    for (Integer i = 1; i <= 12; i++) {
      bs.add(booking(c.Id, 'Completed', -i - 1, -i));
    }
    insert bs;
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 12; i++) {
      cases.add(kase(c.Id, null, 'New', 'Case ' + i));
    }
    insert cases;
    PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
      c.Id
    );
    Assert.areEqual(5, g.upcomingStays.items.size());
    Assert.areEqual(
      Date.today().addDays(1),
      g.upcomingStays.items[0].startDate
    );
    Assert.areEqual(
      Date.today().addDays(5),
      g.upcomingStays.items[4].startDate
    );
    Assert.areEqual(10, g.pastStays.items.size());
    Assert.areEqual(
      Date.today().addDays(-1),
      g.pastStays.items[0].endDate,
      'most recent past stay first'
    );
    Assert.areEqual(Date.today().addDays(-10), g.pastStays.items[9].endDate);
    Assert.areEqual(10, g.service.items.size());
  }

  @isTest
  static void spaceNameIsReturnedWhenSpaceSet() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    Contact c = guest('Spaced');
    PMS_Booking__c b = booking(c.Id, 'Confirmed', 3, 5);
    b.Space__c = h.rooms[0].Id;
    insert b;
    PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
      c.Id
    );
    Assert.areEqual(1, g.upcomingStays.items.size());
    Assert.areEqual('101', g.upcomingStays.items[0].spaceName);
  }

  @isTest
  static void casesOpenFirstAndReachedViaBookingOnly() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Cases');
    Contact other = guest('CasesOther');
    PMS_Booking__c b = booking(c.Id, 'Confirmed', 3, 5);
    PMS_Booking__c otherBooking = booking(other.Id, 'Confirmed', 3, 5);
    insert new List<PMS_Booking__c>{ b, otherBooking };
    Case closed = kase(c.Id, null, 'Closed', 'closed direct');
    Case viaBooking = kase(null, b.Id, 'New', 'open via booking only');
    Case open = kase(c.Id, null, 'New', 'open direct');
    Case unrelated = kase(other.Id, otherBooking.Id, 'New', 'not ours');
    insert new List<Case>{ closed, viaBooking, open, unrelated };
    PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
      c.Id
    );
    Assert.isTrue(g.service.accessible);
    List<PMS_Guest360Controller.ServiceCase> items = g.service.items;
    Assert.areEqual(3, items.size());
    Assert.isFalse(items[0].isClosed, 'open cases first');
    Assert.isFalse(items[1].isClosed, 'open cases first');
    Assert.isTrue(items[2].isClosed);
    Set<Id> ids = new Set<Id>();
    for (PMS_Guest360Controller.ServiceCase sc : items) {
      ids.add(sc.caseId);
      Assert.isNotNull(sc.caseNumber);
      Assert.isNotNull(sc.createdDate);
    }
    Assert.isTrue(ids.contains(viaBooking.Id));
    Assert.isFalse(ids.contains(unrelated.Id));
    for (PMS_Guest360Controller.ServiceCase sc : items) {
      if (sc.caseId == viaBooking.Id) {
        Assert.areEqual(b.Id, sc.bookingId);
        Assert.areEqual('New', sc.status);
        Assert.areEqual('open via booking only', sc.subject);
      }
    }
  }

  @isTest
  static void inactivePreferencesAreExcluded() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Prefs');
    insert new List<PMS_Guest_Preference__c>{
      pref(c.Id, 'Room', 'High floor', Date.today(), true),
      pref(c.Id, 'Room', 'Old preference', Date.today().addDays(-30), false),
      pref(c.Id, 'Food & Drink', 'Vegan', Date.today().addDays(-2), true)
    };
    PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
      c.Id
    );
    Assert.isTrue(g.preferences.accessible);
    Assert.areEqual(2, g.preferences.items.size());
    for (PMS_Guest360Controller.Preference p : g.preferences.items) {
      Assert.areNotEqual('Old preference', p.value);
      Assert.isNotNull(p.preferenceId);
      Assert.areEqual('Staff', p.source);
      Assert.isNotNull(p.capturedOn);
    }
    Assert.areEqual(
      'Room',
      g.preferences.items[0].category,
      'picklist definition order'
    );
    Assert.areEqual('Food & Drink', g.preferences.items[1].category);
  }

  @isTest
  static void latestGdprFormWinsAndOtherFormTypesAreIgnored() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Consent');
    PMS_Intake_Form__c oldGdpr = new PMS_Intake_Form__c(
      Contact__c = c.Id,
      Form_Type__c = 'GDPR Consent',
      Consent_Given__c = true
    );
    PMS_Intake_Form__c newGdpr = new PMS_Intake_Form__c(
      Contact__c = c.Id,
      Form_Type__c = 'GDPR Consent',
      Consent_Given__c = false
    );
    PMS_Intake_Form__c kyc = new PMS_Intake_Form__c(
      Contact__c = c.Id,
      Form_Type__c = 'KYC',
      Consent_Given__c = true
    );
    insert new List<PMS_Intake_Form__c>{ oldGdpr, newGdpr, kyc };
    Datetime newest = Datetime.now().addDays(-1);
    Test.setCreatedDate(oldGdpr.Id, Datetime.now().addDays(-10));
    Test.setCreatedDate(newGdpr.Id, newest);
    Test.setCreatedDate(kyc.Id, Datetime.now().addHours(-1)); // newest overall, wrong type
    PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
      c.Id
    );
    Assert.isTrue(g.consent.formAccessible);
    Assert.areEqual(false, g.consent.gdprFormConsentGiven);
    Assert.areEqual(newest, g.consent.gdprFormDate);
  }

  @isTest
  static void noGdprFormLeavesFormConsentNull() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('NoForm');
    insert new PMS_Intake_Form__c(
      Contact__c = c.Id,
      Form_Type__c = 'KYC',
      Consent_Given__c = true
    );
    PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
      c.Id
    );
    Assert.isTrue(g.consent.formAccessible);
    Assert.isNull(g.consent.gdprFormConsentGiven);
    Assert.isNull(g.consent.gdprFormDate);
  }

  @isTest
  static void identityStatsAndConsentFieldsArePopulated() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Account a = PMS_TestDataFactory.account('Identity Co');
    Datetime refreshed = Datetime.now().addDays(-1);
    Datetime consentOn = Datetime.now().addDays(-20);
    Contact c = new Contact(
      AccountId = a.Id,
      FirstName = 'Ada',
      LastName = 'Lovelace',
      Email = 'ada@example.com',
      Phone = '555-0100',
      PMS_Language__c = 'English',
      PMS_VIP_Level__c = 'VIP 2',
      PMS_VIP_Notes__c = 'Likes tea',
      PMS_Dietary__c = 'Vegan',
      PMS_Accessibility_Needs__c = 'Step-free',
      PMS_ID_Verified__c = true,
      PMS_Total_Stays__c = 4,
      PMS_Lifetime_Nights__c = 12,
      PMS_Room_Revenue__c = 9000,
      PMS_Extras_Revenue__c = 800,
      PMS_First_Stay__c = Date.today().addDays(-400),
      PMS_Last_Stay__c = Date.today().addDays(-30),
      PMS_Next_Arrival__c = Date.today().addDays(14),
      PMS_Stats_Refreshed__c = refreshed,
      PMS_Marketing_Consent__c = true,
      PMS_Consent_Date__c = consentOn,
      PMS_Consent_Source__c = 'Portal',
      PMS_Do_Not_Contact__c = true
    );
    insert c;
    PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
      c.Id
    );
    PMS_Guest360Controller.Identity i = g.identity;
    Assert.areEqual(c.Id, i.contactId);
    Assert.areEqual('Ada Lovelace', i.name);
    Assert.areEqual('ada@example.com', i.email);
    Assert.areEqual('555-0100', i.phone);
    Assert.areEqual('Identity Co', i.accountName);
    Assert.areEqual('English', i.language);
    Assert.areEqual('VIP 2', i.vipLevel);
    Assert.areEqual('Likes tea', i.vipNotes);
    Assert.areEqual('Vegan', i.dietary);
    Assert.areEqual('Step-free', i.accessibilityNeeds);
    Assert.areEqual(true, i.idVerified);
    PMS_Guest360Controller.Stats s = g.stats;
    Assert.isTrue(s.accessible);
    Assert.areEqual(4, s.totalStays);
    Assert.areEqual(12, s.lifetimeNights);
    Assert.areEqual(9000, s.roomRevenue);
    Assert.areEqual(800, s.extrasRevenue);
    Assert.areEqual(Date.today().addDays(-400), s.firstStay);
    Assert.areEqual(Date.today().addDays(-30), s.lastStay);
    Assert.areEqual(Date.today().addDays(14), s.nextArrival);
    Assert.areEqual(refreshed, s.refreshedOn);
    PMS_Guest360Controller.Consent k = g.consent;
    Assert.isTrue(k.accessible);
    Assert.areEqual(true, k.marketingConsent);
    Assert.areEqual(consentOn, k.consentDate);
    Assert.areEqual('Portal', k.consentSource);
    Assert.areEqual(true, k.doNotContact);
    Assert.isTrue(g.upcomingStays.items.isEmpty());
    Assert.isTrue(g.pastStays.items.isEmpty());
    Assert.isTrue(g.service.items.isEmpty());
  }

  // ---------- guest card ----------
  @isTest
  static void cardShowsTopThreeActivePreferencesNewestFirst() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('CardPrefs');
    c.PMS_VIP_Level__c = 'VIP 3';
    c.PMS_Dietary__c = 'Halal';
    c.PMS_Accessibility_Needs__c = 'Hearing loop';
    c.PMS_ID_Verified__c = true;
    c.PMS_Next_Arrival__c = Date.today().addDays(9);
    update c;
    insert new List<PMS_Guest_Preference__c>{
      pref(c.Id, 'Room', 'p-3days', Date.today().addDays(-3), true),
      pref(c.Id, 'Room', 'p-1day', Date.today().addDays(-1), true),
      pref(c.Id, 'Amenities', 'p-inactive-newest', Date.today(), false),
      pref(c.Id, 'Other', 'p-10days', Date.today().addDays(-10), true),
      pref(c.Id, 'Occasion', 'p-5days', Date.today().addDays(-5), true)
    };
    PMS_Guest360Controller.GuestCard card = PMS_Guest360Controller.getGuestCard(
      c.Id
    );
    Assert.areEqual(c.Id, card.contactId);
    Assert.areEqual('CardPrefs', card.name);
    Assert.areEqual('VIP 3', card.vipLevel);
    Assert.areEqual('Halal', card.dietary);
    Assert.areEqual('Hearing loop', card.accessibilityNeeds);
    Assert.areEqual(true, card.idVerified);
    Assert.areEqual(Date.today().addDays(9), card.nextArrival);
    Assert.areEqual(3, card.topPreferences.size());
    Assert.areEqual('p-1day', card.topPreferences[0].value);
    Assert.areEqual('p-3days', card.topPreferences[1].value);
    Assert.areEqual('p-5days', card.topPreferences[2].value);
  }

  @isTest
  static void cardBalanceSumsOnlyLiveUpcomingBookings() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('CardBalance');
    Contact other = guest('CardPayer');
    List<PMS_Booking__c> bs = new List<PMS_Booking__c>{
      money(booking(c.Id, 'Confirmed', 3, 5), 500, 100), // 400
      money(booking(other.Id, 'Active', -1, 2), 300, 0), // party-only, excluded
      money(booking(c.Id, 'Tentative', 4, 6), 200, 0), // 200
      money(booking(c.Id, 'Inquiry', 4, 6), 150, 0), // excluded
      money(booking(c.Id, 'Cancelled', 6, 8), 999, 0), // excluded
      money(booking(c.Id, 'No Show', 9, 10), 888, 0), // excluded
      money(booking(c.Id, 'Completed', -9, -7), 700, 0) // past, excluded
    };
    insert bs;
    insert new PMS_Booking_Party__c(Booking__c = bs[1].Id, Contact__c = c.Id);
    PMS_Guest360Controller.GuestCard card = PMS_Guest360Controller.getGuestCard(
      c.Id
    );
    Assert.isTrue(card.balanceAccessible);
    Assert.areEqual(
      600,
      card.balanceDue,
      'primary Tentative/Confirmed/Active only'
    );
  }

  @isTest
  static void cardWithNoBookingsHasZeroBalanceAndNoArrival() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('CardEmpty');
    PMS_Guest360Controller.GuestCard card = PMS_Guest360Controller.getGuestCard(
      c.Id
    );
    Assert.isTrue(card.balanceAccessible);
    Assert.areEqual(0, card.balanceDue);
    Assert.isNull(card.nextArrival);
    Assert.isTrue(card.topPreferences.isEmpty());
  }

  // ---------- errors ----------
  @isTest
  static void nullAccountAndDeletedContactIdsThrowGenericError() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Account a = PMS_TestDataFactory.account('Not a contact');
    Contact gone = guest('Gone');
    delete gone;
    for (Boolean card : new List<Boolean>{ false, true }) {
      assertGeneric(null, card);
      assertGeneric(a.Id, card);
      assertGeneric(gone.Id, card);
    }
  }

  // ---------- restricted users ----------
  @isTest
  static void viewerWithBaseAccessGetsFullData() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    User u = makeUser('g360full', profileId('Standard User'));
    grantPmsRead(u.Id, true, true);
    Contact c = scenario(u.Id);
    Test.startTest();
    System.runAs(u) {
      PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
        c.Id
      );
      Assert.areEqual('Scenario', g.identity.name);
      Assert.areEqual('Scenario Acc', g.identity.accountName);
      Assert.areEqual('VIP 1', g.identity.vipLevel);
      Assert.isTrue(g.stats.accessible);
      Assert.areEqual(3, g.stats.totalStays);
      Assert.isTrue(g.consent.accessible);
      Assert.areEqual(true, g.consent.marketingConsent);
      Assert.isTrue(g.upcomingStays.accessible);
      Assert.areEqual(2, g.upcomingStays.items.size());
      Assert.areEqual(400, g.upcomingStays.items[0].balanceDue);
      Assert.areEqual(1, g.pastStays.items.size());
      Assert.isTrue(g.preferences.accessible);
      Assert.areEqual(1, g.preferences.items.size());
      Assert.isTrue(g.service.accessible);
      Assert.areEqual(1, g.service.items.size());
      Assert.isTrue(g.consent.formAccessible);
      Assert.areEqual(true, g.consent.gdprFormConsentGiven);

      PMS_Guest360Controller.GuestCard card = PMS_Guest360Controller.getGuestCard(
        c.Id
      );
      Assert.areEqual('VIP 1', card.vipLevel);
      Assert.isTrue(card.balanceAccessible);
      Assert.areEqual(400, card.balanceDue, 'cancelled and past excluded');
      Assert.areEqual(1, card.topPreferences.size());
    }
    Test.stopTest();
  }

  @isTest
  static void contactReaderWithoutPmsPermissionsGetsEmptySectionsNotException() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    User u = makeUser('g360none', profileId('Standard User'));
    Contact c = scenario(u.Id);
    System.runAs(u) {
      PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
        c.Id
      );
      Assert.areEqual('Scenario', g.identity.name);
      Assert.areEqual('scenario@example.com', g.identity.email);
      Assert.areEqual('Scenario Acc', g.identity.accountName);
      Assert.isNull(g.identity.vipLevel);
      Assert.isNull(g.identity.dietary);
      Assert.isNull(g.identity.idVerified);
      Assert.isFalse(g.stats.accessible);
      Assert.isNull(g.stats.totalStays);
      Assert.isNull(g.stats.roomRevenue);
      Assert.isFalse(g.consent.accessible);
      Assert.isNull(g.consent.marketingConsent);
      Assert.isFalse(g.consent.formAccessible);
      Assert.isNull(g.consent.gdprFormConsentGiven);
      Assert.isFalse(g.upcomingStays.accessible);
      Assert.isFalse(g.pastStays.accessible);
      Assert.isTrue(g.upcomingStays.items.isEmpty());
      Assert.isTrue(g.pastStays.items.isEmpty());
      Assert.isFalse(g.preferences.accessible);
      Assert.isTrue(g.preferences.items.isEmpty());
      for (PMS_Guest360Controller.ServiceCase sc : g.service.items) {
        Assert.isNull(sc.bookingId, 'PMS_Booking__c on Case is FLS-stripped');
      }

      PMS_Guest360Controller.GuestCard card = PMS_Guest360Controller.getGuestCard(
        c.Id
      );
      Assert.areEqual('Scenario', card.name);
      Assert.isNull(card.vipLevel);
      Assert.isNull(card.nextArrival);
      Assert.isTrue(card.topPreferences.isEmpty());
      Assert.isFalse(card.balanceAccessible);
      Assert.isNull(card.balanceDue);
    }
  }

  @isTest
  static void userWithoutContactReadGetsGenericError() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Id minimal = profileId('Minimum Access - Salesforce');
    if (minimal == null) {
      System.debug(
        LoggingLevel.WARN,
        'Skipped: Minimum Access profile not found'
      );
      return;
    }
    User u = makeUser('g360nocn', minimal);
    Contact c = guest('NoContactRead');
    System.runAs(u) {
      if (Contact.SObjectType.getDescribe().isAccessible()) {
        System.debug(
          LoggingLevel.WARN,
          'Skipped: profile unexpectedly reads Contact'
        );
        return;
      }
      assertGeneric(c.Id, false);
      assertGeneric(c.Id, true);
    }
  }

  @isTest
  static void userMissingBalanceFlsSeesNullBalance() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    User u = makeUser('g360nbal', profileId('Standard User'));
    grantPmsRead(u.Id, true, false);
    Contact c = scenario(u.Id);
    System.runAs(u) {
      PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
        c.Id
      );
      Assert.areEqual(2, g.upcomingStays.items.size());
      for (PMS_Guest360Controller.Stay s : g.upcomingStays.items) {
        Assert.isNull(s.balanceDue);
        Assert.isNotNull(s.totalAmount);
      }
      PMS_Guest360Controller.GuestCard card = PMS_Guest360Controller.getGuestCard(
        c.Id
      );
      Assert.isFalse(card.balanceAccessible);
      Assert.isNull(card.balanceDue);
    }
  }

  @isTest
  static void sharingHiddenContactGetsGenericErrorWhenOwdIsPrivate() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    User u = makeUser('g360hide', profileId('Standard User'));
    Contact c = guest('Hidden'); // owned by the test runner, not by u
    System.runAs(u) {
      if (![SELECT Id FROM Contact WHERE Id = :c.Id].isEmpty()) {
        System.debug(
          LoggingLevel.WARN,
          'Skipped: Contact OWD is public in this org, record is visible'
        );
        return;
      }
      assertGeneric(c.Id, false);
      assertGeneric(c.Id, true);
    }
  }

  @isTest
  static void todayBoundaryAndPartyOnlyCaseRules() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Boundary');
    Contact other = guest('BoundaryPayer');
    Datetime todayStart = Datetime.newInstance(
      Date.today(),
      Time.newInstance(0, 0, 0, 0)
    );
    PMS_Booking__c endsToday = booking(c.Id, 'Active', -2, 0);
    endsToday.End__c = at(0);
    PMS_Booking__c endsAtMidnight = booking(c.Id, 'Active', -3, 0);
    endsAtMidnight.End__c = todayStart;
    PMS_Booking__c endedYesterday = booking(c.Id, 'Completed', -4, -1);
    endedYesterday.End__c = todayStart.addMinutes(-1);
    PMS_Booking__c partyOnly = booking(other.Id, 'Confirmed', 2, 4);
    insert new List<PMS_Booking__c>{
      endsToday,
      endsAtMidnight,
      endedYesterday,
      partyOnly
    };
    insert new PMS_Booking_Party__c(
      Booking__c = partyOnly.Id,
      Contact__c = c.Id
    );
    Case partyBookingOnly = kase(
      null,
      partyOnly.Id,
      'New',
      'party booking only'
    );
    Case partyBookingWithContact = kase(
      c.Id,
      partyOnly.Id,
      'New',
      'with contact'
    );
    insert new List<Case>{ partyBookingOnly, partyBookingWithContact };
    PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
      c.Id
    );
    Set<Id> up = stayIds(g.upcomingStays.items);
    Assert.isTrue(up.contains(endsToday.Id));
    Assert.isTrue(up.contains(endsAtMidnight.Id));
    Assert.isFalse(up.contains(endedYesterday.Id));
    Assert.areEqual(1, g.pastStays.items.size());
    Assert.areEqual(endedYesterday.Id, g.pastStays.items[0].bookingId);
    Set<Id> caseIds = new Set<Id>();
    for (PMS_Guest360Controller.ServiceCase sc : g.service.items) {
      caseIds.add(sc.caseId);
    }
    Assert.isFalse(
      caseIds.contains(partyBookingOnly.Id),
      'party-only booking case hidden'
    );
    Assert.isTrue(caseIds.contains(partyBookingWithContact.Id));
  }

  @isTest
  static void userWithoutPartyAccessStillGetsPrimaryStays() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    User u = makeUser('g360nopt', profileId('Standard User'));
    includePartyAccess = false;
    grantPmsRead(u.Id, true, true);
    Contact c = scenario(u.Id);
    Contact other = guest('NoPartyPayer');
    PMS_Booking__c partyOnly = booking(other.Id, 'Confirmed', 2, 4);
    insert partyOnly;
    insert new PMS_Booking_Party__c(
      Booking__c = partyOnly.Id,
      Contact__c = c.Id
    );
    System.runAs(u) {
      PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
        c.Id
      );
      Assert.isTrue(g.upcomingStays.accessible);
      Assert.areEqual(2, g.upcomingStays.items.size(), 'primary stays only');
      Assert.isFalse(stayIds(g.upcomingStays.items).contains(partyOnly.Id));
      Assert.areEqual(1, g.pastStays.items.size());
      PMS_Guest360Controller.GuestCard card = PMS_Guest360Controller.getGuestCard(
        c.Id
      );
      Assert.areEqual(400, card.balanceDue);
    }
  }

  // ---------- bulk ----------
  @isTest
  static void guestWithOver200PartyBookingsStaysWithinLimits() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('BulkGuest');
    Contact payer = guest('BulkPayer');
    List<PMS_Booking__c> bs = new List<PMS_Booking__c>();
    for (Integer i = 0; i < 210; i++) {
      bs.add(
        i < 105
          ? booking(payer.Id, 'Confirmed', i + 1, i + 2)
          : booking(payer.Id, 'Completed', -(i - 104) - 1, -(i - 104))
      );
    }
    insert bs;
    List<PMS_Booking_Party__c> parties = new List<PMS_Booking_Party__c>();
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 210; i++) {
      parties.add(
        new PMS_Booking_Party__c(Booking__c = bs[i].Id, Contact__c = c.Id)
      );
    }
    for (Integer i = 0; i < 12; i++) {
      cases.add(kase(c.Id, bs[i].Id, 'New', 'bulk case ' + i));
    }
    insert parties;
    insert cases;
    Test.startTest();
    Integer q0 = Limits.getQueries();
    PMS_Guest360Controller.Guest360 g = PMS_Guest360Controller.getGuest360(
      c.Id
    );
    Integer used360 = Limits.getQueries() - q0;
    Integer q1 = Limits.getQueries();
    PMS_Guest360Controller.GuestCard card = PMS_Guest360Controller.getGuestCard(
      c.Id
    );
    Integer usedCard = Limits.getQueries() - q1;
    Test.stopTest();
    Assert.isTrue(used360 <= 8, 'getGuest360 queries: ' + used360);
    Assert.isTrue(usedCard <= 3, 'getGuestCard queries: ' + usedCard);
    Assert.areEqual(5, g.upcomingStays.items.size());
    Assert.areEqual(10, g.pastStays.items.size());
    Assert.areEqual(10, g.service.items.size());
    Assert.areEqual(5, stayIds(g.upcomingStays.items).size());
    Assert.areEqual(
      0,
      card.balanceDue,
      'party-only bookings do not count toward balance'
    );
  }
}
