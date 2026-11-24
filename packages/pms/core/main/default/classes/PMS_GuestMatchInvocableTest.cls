@isTest
private class PMS_GuestMatchInvocableTest {
  private static PMS_GuestMatchInvocable.Request req(
    String first,
    String last,
    String email,
    String phone,
    String role
  ) {
    PMS_GuestMatchInvocable.Request q = new PMS_GuestMatchInvocable.Request();
    q.firstName = first;
    q.lastName = last;
    q.email = email;
    q.phone = phone;
    q.partyRole = role;
    return q;
  }

  private static List<PMS_GuestMatchInvocable.Response> run(
    List<PMS_GuestMatchInvocable.Request> rs
  ) {
    Test.startTest();
    List<PMS_GuestMatchInvocable.Response> out = PMS_GuestMatchInvocable.findOrCreate(
      rs
    );
    Test.stopTest();
    return out;
  }

  private static User userWithProfile(String profileName) {
    Id profId = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1].Id;
    String alias = 'gm' + String.valueOf(Crypto.getRandomInteger()).right(6);
    User u = new User(
      Alias = alias.left(8),
      Email = alias + '@pms-gm.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'GM ' + alias,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profId,
      TimeZoneSidKey = 'GMT',
      Username = alias + '.' + Crypto.getRandomInteger() + '@pms-gm.test'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
    }
    return u;
  }

  @isTest
  static void emptyRequestsReturnEmptyList() {
    Assert.areEqual(0, PMS_GuestMatchInvocable.findOrCreate(null).size());
    Assert.areEqual(
      0,
      PMS_GuestMatchInvocable.findOrCreate(
          new List<PMS_GuestMatchInvocable.Request>()
        )
        .size()
    );
  }

  @isTest
  static void newGuestCreatesAccountAndContact() {
    List<PMS_GuestMatchInvocable.Response> out = run(
      new List<PMS_GuestMatchInvocable.Request>{
        req('Karin', 'Ek', 'karin@guest.example.com', '+46701112233', null)
      }
    );
    Assert.areEqual(1, out.size());
    Assert.isTrue(out[0].isNew);
    Contact c = [
      SELECT
        AccountId,
        Email,
        Phone,
        FirstName,
        PMS_Possible_Duplicate_Of__c,
        Account.Name,
        Account.PMS_Party_Role__c,
        Account.Phone
      FROM Contact
      WHERE Id = :out[0].contactId
    ];
    Assert.areEqual(out[0].accountId, c.AccountId);
    Assert.areEqual('karin@guest.example.com', c.Email);
    Assert.areEqual('Karin Ek', c.Account.Name);
    Assert.areEqual('Guest', c.Account.PMS_Party_Role__c, 'default role');
    Assert.areEqual('+46701112233', c.Account.Phone);
    Assert.isNull(c.PMS_Possible_Duplicate_Of__c);
  }

  @isTest
  static void partyRoleIsUsedAndLastNameOnlyNameIsTrimmed() {
    List<PMS_GuestMatchInvocable.Response> out = run(
      new List<PMS_GuestMatchInvocable.Request>{
        req(null, 'Tenant', null, null, 'Tenant')
      }
    );
    Account a = [
      SELECT Name, PMS_Party_Role__c
      FROM Account
      WHERE Id = :out[0].accountId
    ];
    Assert.areEqual('Tenant', a.Name);
    Assert.areEqual('Tenant', a.PMS_Party_Role__c);
  }

  @isTest
  static void existingGuestIsMatchedByEmailWithoutCreatingRecords() {
    Account a = PMS_TestDataFactory.account('Existing');
    Contact c = new Contact(
      AccountId = a.Id,
      LastName = 'Existing',
      Email = 'exists@guest.example.com'
    );
    insert c;
    Integer accs = [SELECT COUNT() FROM Account];
    Integer cons = [SELECT COUNT() FROM Contact];
    List<PMS_GuestMatchInvocable.Response> out = run(
      new List<PMS_GuestMatchInvocable.Request>{
        req('Any', 'Name', 'EXISTS@guest.example.com', null, null)
      }
    );
    Assert.areEqual(c.Id, out[0].contactId);
    Assert.areEqual(a.Id, out[0].accountId);
    Assert.isFalse(out[0].isNew);
    Assert.areEqual(accs, [SELECT COUNT() FROM Account]);
    Assert.areEqual(cons, [SELECT COUNT() FROM Contact]);
  }

  @isTest
  static void maskedEmailCreatesNewContactWithAliasAndBlankEmail() {
    Account a = PMS_TestDataFactory.account('Relay');
    insert new Contact(
      AccountId = a.Id,
      LastName = 'Relay',
      Email = 'r1@guest.booking.com'
    );
    List<PMS_GuestMatchInvocable.Response> out = run(
      new List<PMS_GuestMatchInvocable.Request>{
        req('R', 'Other', 'r1@guest.booking.com', null, null)
      }
    );
    Assert.isTrue(out[0].isNew);
    Contact c = [
      SELECT Email, PMS_OTA_Alias_Email__c
      FROM Contact
      WHERE Id = :out[0].contactId
    ];
    Assert.isNull(c.Email);
    Assert.areEqual('r1@guest.booking.com', c.PMS_OTA_Alias_Email__c);
  }

  @isTest
  static void possibleDuplicateIsFlaggedOnNewContactNotMerged() {
    Account a = PMS_TestDataFactory.account('Dup');
    Contact orig = new Contact(
      AccountId = a.Id,
      FirstName = 'Dora',
      LastName = 'Dup',
      Phone = '+46709998877'
    );
    insert orig;
    List<PMS_GuestMatchInvocable.Response> out = run(
      new List<PMS_GuestMatchInvocable.Request>{
        req('Dora', 'Dup', null, '0046709998877', null)
      }
    );
    Assert.isTrue(out[0].isNew);
    Assert.areNotEqual(orig.Id, out[0].contactId);
    Contact c = [
      SELECT PMS_Possible_Duplicate_Of__c, PMS_Duplicate_Reason__c
      FROM Contact
      WHERE Id = :out[0].contactId
    ];
    Assert.areEqual(orig.Id, c.PMS_Possible_Duplicate_Of__c);
    Assert.areEqual('Same name and phone number.', c.PMS_Duplicate_Reason__c);
  }

  @isTest
  static void phoneAndNameMatchWhenSettingOn() {
    PMS_Settings__c st = PMS_Settings__c.getOrgDefaults();
    st.Guest_Match_Phone_Name__c = true;
    upsert st;
    Account a = PMS_TestDataFactory.account('Pm');
    Contact orig = new Contact(
      AccountId = a.Id,
      FirstName = 'Pam',
      LastName = 'Pm',
      Phone = '+46705554433'
    );
    insert orig;
    List<PMS_GuestMatchInvocable.Response> out = run(
      new List<PMS_GuestMatchInvocable.Request>{
        req('P', 'Pm', null, '+46 70 555 44 33', null)
      }
    );
    Assert.isFalse(out[0].isNew);
    Assert.areEqual(orig.Id, out[0].contactId);
    Assert.areEqual(a.Id, out[0].accountId);
  }

  @isTest
  static void bulkMixOf200KeepsOrderAndStaysInLimits() {
    Account a = PMS_TestDataFactory.account('Bulk');
    List<Contact> existing = new List<Contact>();
    for (Integer i = 0; i < 100; i++) {
      existing.add(
        new Contact(
          AccountId = a.Id,
          LastName = 'B' + i,
          Email = 'b' + i + '@guest.example.com'
        )
      );
    }
    insert existing;
    List<PMS_GuestMatchInvocable.Request> rs = new List<PMS_GuestMatchInvocable.Request>();
    for (Integer i = 0; i < 200; i++) {
      rs.add(
        Math.mod(i, 2) == 0
          ? req('F', 'B' + i, 'b' + (i / 2) + '@guest.example.com', null, null)
          : req('N' + i, 'Nw' + i, 'n' + i + '@guest.example.com', null, null)
      );
    }
    List<PMS_GuestMatchInvocable.Response> out = run(rs);
    Assert.areEqual(200, out.size());
    for (Integer i = 0; i < 200; i++) {
      if (Math.mod(i, 2) == 0) {
        Assert.isFalse(out[i].isNew, 'row ' + i);
        Assert.areEqual(existing[i / 2].Id, out[i].contactId);
      } else {
        Assert.isTrue(out[i].isNew, 'row ' + i);
        Assert.isNotNull(out[i].accountId);
      }
    }
  }

  @isTest
  static void userWithoutCreateAccessCannotCreateGuests() {
    User u = userWithProfile('Minimum Access - Salesforce');
    Boolean denied = false;
    System.runAs(u) {
      try {
        PMS_GuestMatchInvocable.findOrCreate(
          new List<PMS_GuestMatchInvocable.Request>{
            req('No', 'Access', null, null, null)
          }
        );
      } catch (Exception e) {
        denied = true;
      }
    }
    Assert.isTrue(
      denied,
      'insert as user must be refused without Account create access'
    );
    Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE Name = 'No Access']);
  }

  /** Standard User plus the shipped PMS_Core_Admin permission set: create and re-match works under USER_MODE. */
  @isTest
  static void pmsUserCanCreateAndMatchOwnGuest() {
    User u = userWithProfile('Standard User');
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'PMS_Core_Admin'
          LIMIT 1
        ]
        .Id
      );
    }
    System.runAs(u) {
      List<PMS_GuestMatchInvocable.Response> first = PMS_GuestMatchInvocable.findOrCreate(
        new List<PMS_GuestMatchInvocable.Request>{
          req('Std', 'User', 'std@guest.example.com', null, null)
        }
      );
      Assert.isTrue(first[0].isNew);
      List<PMS_GuestMatchInvocable.Response> again = PMS_GuestMatchInvocable.findOrCreate(
        new List<PMS_GuestMatchInvocable.Request>{
          req('Std', 'User', 'std@guest.example.com', null, null)
        }
      );
      Assert.isFalse(again[0].isNew);
      Assert.areEqual(first[0].contactId, again[0].contactId);
      Assert.areEqual(first[0].accountId, again[0].accountId);
    }
  }

  /** Documents that PMS_Party_Role__c FLS is required: a plain Standard User is refused by USER_MODE. */
  @isTest
  static void standardUserWithoutPmsPermissionIsRefusedOnPartyRoleField() {
    User u = userWithProfile('Standard User');
    Boolean denied = false;
    System.runAs(u) {
      try {
        PMS_GuestMatchInvocable.findOrCreate(
          new List<PMS_GuestMatchInvocable.Request>{
            req('Std', 'Plain', null, null, null)
          }
        );
      } catch (DmlException e) {
        denied = true;
      }
    }
    Assert.isTrue(denied);
  }
}
