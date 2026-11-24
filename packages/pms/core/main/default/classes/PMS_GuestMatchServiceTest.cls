@isTest
private class PMS_GuestMatchServiceTest {
  private static PMS_GuestMatchService.GuestInput input(
    String first,
    String last,
    String email,
    String phone
  ) {
    PMS_GuestMatchService.GuestInput g = new PMS_GuestMatchService.GuestInput();
    g.firstName = first;
    g.lastName = last;
    g.email = email;
    g.phone = phone;
    return g;
  }

  private static PMS_GuestMatchService.Result matchOne(
    PMS_GuestMatchService.GuestInput g
  ) {
    return PMS_GuestMatchService.match(
      new List<PMS_GuestMatchService.GuestInput>{ g }
    )[0];
  }

  private static Contact guest(
    String first,
    String last,
    String email,
    String phone
  ) {
    Account a = PMS_TestDataFactory.account('Acc ' + first + last);
    Contact c = new Contact(
      AccountId = a.Id,
      FirstName = first,
      LastName = last,
      Email = email,
      Phone = phone
    );
    Database.DMLOptions opts = new Database.DMLOptions();
    opts.DuplicateRuleHeader.allowSave = true;
    Database.insert(c, opts);
    return c;
  }

  private static void phoneRule(Boolean enabled) {
    PMS_Settings__c st = PMS_Settings__c.getOrgDefaults();
    st.Guest_Match_Phone_Name__c = enabled;
    upsert st;
  }

  private static Datetime at(Integer dayOffset) {
    return Datetime.newInstance(
      Date.today().addDays(dayOffset),
      Time.newInstance(12, 0, 0, 0)
    );
  }

  private static void stay(Id contactId, String status, Integer s, Integer e) {
    insert new PMS_Booking__c(
      Primary_Contact__c = contactId,
      Status__c = status,
      Start__c = at(s),
      End__c = at(e)
    );
  }

  private static PMS_GuestMatchService.GuestInput withStay(
    PMS_GuestMatchService.GuestInput g,
    Integer arr,
    Integer dep
  ) {
    g.arrival = Date.today().addDays(arr);
    g.departure = Date.today().addDays(dep);
    return g;
  }

  // ---------------------------------------------------------------- isMasked

  @isTest
  static void isMaskedCoversConfiguredDomainsSubdomainsAndCase() {
    for (String d : PMS_GuestMatchService.MASKED_DOMAINS) {
      Assert.isTrue(PMS_GuestMatchService.isMasked('x@' + d), d);
      Assert.isTrue(PMS_GuestMatchService.isMasked('x@sub.' + d), 'sub ' + d);
      Assert.isTrue(
        PMS_GuestMatchService.isMasked('X@' + d.toUpperCase()),
        'upper ' + d
      );
    }
    Assert.isTrue(PMS_GuestMatchService.isMasked(' x@GUEST.Booking.com '));
  }

  @isTest
  static void isMaskedRejectsLookAlikesAndBlanks() {
    Assert.isFalse(PMS_GuestMatchService.isMasked('a@booking.com'));
    Assert.isFalse(
      PMS_GuestMatchService.isMasked('a@guest.booking.com.example.org')
    );
    Assert.isFalse(PMS_GuestMatchService.isMasked('a@notguest.booking.com'));
    Assert.isFalse(PMS_GuestMatchService.isMasked('a@notguest.airbnb.com'));
    Assert.isFalse(PMS_GuestMatchService.isMasked('a@example.com'));
    Assert.isFalse(PMS_GuestMatchService.isMasked(null));
    Assert.isFalse(PMS_GuestMatchService.isMasked(''));
    Assert.isFalse(PMS_GuestMatchService.isMasked('no-at-sign'));
  }

  // ---------------------------------------------------------- normalisePhone

  @isTest
  static void normalisePhoneFormats() {
    Assert.areEqual(
      '+46701234567',
      PMS_GuestMatchService.normalisePhone('0046 70-123 45 67')
    );
    Assert.areEqual(
      '+46701234567',
      PMS_GuestMatchService.normalisePhone('+46 (70) 123-4567')
    );
    Assert.areEqual(
      '0701234567',
      PMS_GuestMatchService.normalisePhone('070 123 45 67'),
      'national stays digits'
    );
    Assert.isNull(PMS_GuestMatchService.normalisePhone('12345'), 'too short');
    Assert.isNull(
      PMS_GuestMatchService.normalisePhone('+12-34'),
      'too short with plus'
    );
    Assert.isNull(PMS_GuestMatchService.normalisePhone('abc'));
    Assert.isNull(PMS_GuestMatchService.normalisePhone(null));
    Assert.isNull(PMS_GuestMatchService.normalisePhone('  '));
  }

  @isTest
  static void foldAndEmptyInputs() {
    Assert.areEqual('', PMS_GuestMatchService.fold(null));
    Assert.areEqual('muller', PMS_GuestMatchService.fold(' MÜLLER '));
    Assert.areEqual(0, PMS_GuestMatchService.match(null).size());
    Assert.areEqual(
      0,
      PMS_GuestMatchService.match(new List<PMS_GuestMatchService.GuestInput>())
        .size()
    );
  }

  // ------------------------------------------------------------------ email

  @isTest
  static void exactEmailIsCaseInsensitiveAndPicksOldestWithAccount() {
    Contact noAccount = new Contact(
      LastName = 'Orphan',
      Email = 'dup@guest.example.com'
    );
    insert noAccount;
    Contact oldest = guest('A', 'One', 'dup@guest.example.com', null);
    Contact newer = guest('B', 'Two', 'dup@guest.example.com', null);
    Test.setCreatedDate(oldest.Id, Datetime.now().addDays(-5));
    Test.setCreatedDate(noAccount.Id, Datetime.now().addDays(-9));

    Test.startTest();
    PMS_GuestMatchService.Result r = matchOne(
      input('X', 'Y', 'DUP@Guest.Example.COM', null)
    );
    Test.stopTest();
    Assert.areEqual(PMS_GuestMatchService.EXACT_EMAIL, r.confidence);
    Assert.areEqual(oldest.Id, r.contactId);
    Assert.areNotEqual(newer.Id, r.contactId);
  }

  @isTest
  static void emailOnlyOnContactWithoutAccountDoesNotMatch() {
    insert new Contact(LastName = 'Orphan', Email = 'orphan@guest.example.com');
    PMS_GuestMatchService.Result r = matchOne(
      input('X', 'Nobody', 'orphan@guest.example.com', null)
    );
    Assert.isNull(r.contactId);
    Assert.areEqual(PMS_GuestMatchService.NONE, r.confidence);
  }

  @isTest
  static void maskedEmailNeverMatchesAndGoesToAlias() {
    String masked = 'abc123@guest.booking.com';
    guest('Anna', 'Masked', masked, null); // stored Email equal to masked relay
    PMS_GuestMatchService.GuestInput g = input(
      'Zed',
      'Unrelated',
      masked,
      null
    );
    PMS_GuestMatchService.Result r = matchOne(g);
    Assert.isNull(r.contactId);
    Assert.areEqual(PMS_GuestMatchService.NONE, r.confidence);
    Assert.areEqual(masked, r.aliasEmail);
    Assert.isNull(r.cleanEmail);

    g.accountId = PMS_TestDataFactory.account('New').Id;
    Contact c = PMS_GuestMatchService.newContact(g, r);
    Assert.areEqual(masked, c.PMS_OTA_Alias_Email__c);
    Assert.isNull(c.Email);
  }

  @isTest
  static void newContactDefaultsLastNameAndCopiesCleanEmail() {
    PMS_GuestMatchService.GuestInput g = input(
      'Solo',
      null,
      'solo@guest.example.com',
      '+4670123456'
    );
    Contact c = PMS_GuestMatchService.newContact(g, matchOne(g));
    Assert.areEqual('Solo', c.LastName);
    Assert.areEqual('solo@guest.example.com', c.Email);
    Assert.isNull(c.PMS_OTA_Alias_Email__c);
    Assert.areEqual(
      'Guest',
      PMS_GuestMatchService.newContact(
          input(null, '', null, null),
          new PMS_GuestMatchService.Result()
        )
        .LastName
    );
  }

  // ------------------------------------------------------------ phone + name

  @isTest
  static void phoneAndLastNameMatchesOnlyWhenSettingIsOn() {
    Contact c = guest(
      'Pia',
      'Lindqvist',
      'pia@guest.example.com',
      '+46 70 123 45 67'
    );
    PMS_GuestMatchService.GuestInput g = input(
      'Other',
      'LINDQVIST',
      null,
      '0046701234567'
    );

    phoneRule(true);
    PMS_GuestMatchService.Result onRes = matchOne(g);
    Assert.areEqual(PMS_GuestMatchService.PHONE_NAME, onRes.confidence);
    Assert.areEqual(c.Id, onRes.contactId);
    Assert.isNull(onRes.possibleDuplicateOf);

    phoneRule(false);
    PMS_GuestMatchService.Result off = matchOne(
      input('Pia', 'Lindqvist', null, '0046701234567')
    );
    Assert.isNull(off.contactId);
    Assert.areEqual(PMS_GuestMatchService.NONE, off.confidence);
    Assert.areEqual(c.Id, off.possibleDuplicateOf);
    Assert.areEqual('Same name and phone number.', off.reason);

    // Same phone, different last name: nothing either way.
    Assert.isNull(
      matchOne(input('Pia', 'Different', null, '0046701234567'))
        .possibleDuplicateOf
    );
  }

  @isTest
  static void phoneMatchIgnoresContactWithoutAccount() {
    phoneRule(true);
    insert new Contact(
      LastName = 'Noacct',
      FirstName = 'N',
      Phone = '+46701234567'
    );
    PMS_GuestMatchService.Result r = matchOne(
      input('N', 'Noacct', null, '+46701234567')
    );
    Assert.isNull(r.contactId, 'contact without account is not a phone match');
  }

  @isTest
  static void phoneNameWinsOverEarlierNameOnlyFlag() {
    phoneRule(true);
    Contact first = guest('Eva', 'Berg', null, '+46700000001'); // same first name, different phone
    Contact target = guest('Eve', 'Berg', null, '+46700000002');
    stay(first.Id, 'Confirmed', 1, 3);
    PMS_GuestMatchService.Result r = matchOne(
      withStay(input('Eva', 'Berg', null, '+46700000002'), 2, 4)
    );
    Assert.areEqual(target.Id, r.contactId);
    Assert.isNull(
      r.possibleDuplicateOf,
      'flag cleared when a real match is found'
    );
    Assert.isNull(r.reason);
  }

  // ------------------------------------------------------- name + stay dates

  @isTest
  static void sameNameWithOverlappingOrAdjacentStayIsFlagged() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Lars', 'Holm', 'lars@guest.example.com', null);
    stay(c.Id, 'Confirmed', 10, 13);

    PMS_GuestMatchService.Result overlap = matchOne(
      withStay(input('lars', 'HOLM', null, null), 12, 15)
    );
    Assert.isNull(overlap.contactId);
    Assert.areEqual(PMS_GuestMatchService.NONE, overlap.confidence);
    Assert.areEqual(c.Id, overlap.possibleDuplicateOf);
    Assert.areEqual(
      'Same name with an overlapping or adjacent stay.',
      overlap.reason
    );

    // Adjacent: arrives the day the other stay ends / one day after.
    Assert.areEqual(
      c.Id,
      matchOne(withStay(input('Lars', 'Holm', null, null), 14, 16))
        .possibleDuplicateOf
    );
    Assert.areEqual(
      c.Id,
      matchOne(withStay(input('Lars', 'Holm', null, null), 7, 9))
        .possibleDuplicateOf
    );
  }

  @isTest
  static void stayAWeekAwayCancelledOrDifferentFirstNameIsNotFlagged() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Lars', 'Holm', null, null);
    stay(c.Id, 'Confirmed', 10, 13);
    Assert.isNull(
      matchOne(withStay(input('Lars', 'Holm', null, null), 20, 22))
        .possibleDuplicateOf,
      'week away'
    );
    Assert.isNull(
      matchOne(withStay(input('Nils', 'Holm', null, null), 10, 13))
        .possibleDuplicateOf,
      'other first name'
    );
    Assert.isNull(
      matchOne(input('Lars', 'Holm', null, null)).possibleDuplicateOf,
      'no dates given'
    );

    Contact d = guest('Mia', 'Strand', null, null);
    stay(d.Id, 'Cancelled', 10, 13);
    Assert.isNull(
      matchOne(withStay(input('Mia', 'Strand', null, null), 10, 13))
        .possibleDuplicateOf,
      'cancelled ignored'
    );
  }

  /**
   * Current behaviour, documented: a stored last name WITH diacritics is not found for plain input,
   * because the SOQL "LastName IN :names" pre-filter is accent-sensitive and only the input is folded.
   * Accented input against a plain stored name does match. If the former is fixed, update this test.
   */
  @isTest
  static void accentedStoredLastNameVersusPlainInputBehaviour() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact accented = guest('Jan', 'Åkesson', null, null);
    stay(accented.Id, 'Confirmed', 10, 13);
    Contact plain = guest('Bo', 'Muller', null, null);
    stay(plain.Id, 'Confirmed', 10, 13);

    PMS_GuestMatchService.Result plainInput = matchOne(
      withStay(input('Jan', 'Akesson', null, null), 10, 13)
    );
    Assert.isNull(
      plainInput.possibleDuplicateOf,
      'known gap: accented stored name missed by plain input'
    );

    PMS_GuestMatchService.Result accentedInput = matchOne(
      withStay(input('Bo', 'Müller', null, null), 10, 13)
    );
    Assert.areEqual(
      plain.Id,
      accentedInput.possibleDuplicateOf,
      'accented input finds plain stored name'
    );

    Assert.areEqual(
      accented.Id,
      matchOne(withStay(input('Jan', 'Åkesson', null, null), 10, 13))
        .possibleDuplicateOf
    );
  }

  // -------------------------------------------------------------------- bulk

  @isTest
  static void bulkOf200UsesAtMostThreeQueries() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Account a = PMS_TestDataFactory.account('Bulk');
    List<Contact> existing = new List<Contact>();
    for (Integer i = 0; i < 200; i++) {
      existing.add(
        new Contact(
          AccountId = a.Id,
          FirstName = 'F' + i,
          LastName = 'L' + i,
          Email = 'g' + i + '@guest.example.com'
        )
      );
    }
    insert existing;
    List<PMS_Booking__c> bookings = new List<PMS_Booking__c>();
    for (Integer i = 100; i < 150; i++) {
      bookings.add(
        new PMS_Booking__c(
          Primary_Contact__c = existing[i].Id,
          Status__c = 'Confirmed',
          Start__c = at(10),
          End__c = at(12)
        )
      );
    }
    insert bookings;

    List<PMS_GuestMatchService.GuestInput> inputs = new List<PMS_GuestMatchService.GuestInput>();
    for (Integer i = 0; i < 200; i++) {
      PMS_GuestMatchService.GuestInput g;
      if (i < 100) {
        g = input('X', 'Y' + i, 'G' + i + '@Guest.Example.com', null); // email matches
      } else if (i < 150) {
        g = withStay(
          input('F' + i, 'L' + i, 'new' + i + '@guest.example.com', null),
          11,
          13
        ); // flagged
      } else {
        g = input(
          'N' + i,
          'M' + i,
          'm' + i + '@guest.booking.com',
          '+4670000' + i
        ); // none
      }
      inputs.add(g);
    }
    Test.startTest();
    Integer before = Limits.getQueries();
    List<PMS_GuestMatchService.Result> res = PMS_GuestMatchService.match(
      inputs
    );
    Integer used = Limits.getQueries() - before;
    Test.stopTest();

    Assert.isTrue(used <= 3, 'queries used: ' + used);
    Assert.areEqual(200, res.size());
    for (Integer i = 0; i < 200; i++) {
      if (i < 100) {
        Assert.areEqual(existing[i].Id, res[i].contactId, 'row ' + i);
      } else if (i < 150) {
        Assert.isNull(res[i].contactId);
        Assert.areEqual(existing[i].Id, res[i].possibleDuplicateOf, 'row ' + i);
      } else {
        Assert.isNull(res[i].contactId);
        Assert.isNull(res[i].possibleDuplicateOf);
        Assert.isNotNull(res[i].aliasEmail);
      }
    }
  }
}
