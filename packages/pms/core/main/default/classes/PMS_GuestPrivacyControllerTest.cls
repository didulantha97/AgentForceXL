@isTest
private class PMS_GuestPrivacyControllerTest {
  private static final List<String> SECTIONS = new List<String>{
    'exportedOn',
    'contactId',
    'contact',
    'contactCustomFields',
    'accounts',
    'preferences',
    'bookingParties',
    'bookingsAsPrimaryGuest',
    'bookingsAsPartyMember',
    'charges',
    'invoices',
    'payments',
    'checkIns',
    'intakeForms',
    'cases',
    'fileNames'
  };

  private class Fx {
    Contact c;
    PMS_Booking__c booking;
    PMS_Booking__c partyBooking;
    Id docId;
  }

  private static Datetime at(Integer dayOffset) {
    return Datetime.newInstance(
      Date.today().addDays(dayOffset),
      Time.newInstance(12, 0, 0, 0)
    );
  }

  private static Fx fixture() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Fx f = new Fx();
    Account a = new Account(
      Name = 'Export Acc',
      PMS_Party_Role__c = 'Guest',
      PMS_Customer_Type__c = 'Consumer',
      Phone = '555'
    );
    insert a;
    f.c = new Contact(
      AccountId = a.Id,
      FirstName = 'Eva',
      LastName = 'Exported',
      Email = 'eva@example.com',
      PMS_VIP_Notes__c = 'vip secret',
      PMS_Dietary__c = 'Vegan'
    );
    insert f.c;
    f.booking = new PMS_Booking__c(
      Primary_Contact__c = f.c.Id,
      Status__c = 'Completed',
      Start__c = at(-10),
      End__c = at(-7),
      Total_Amount__c = 100,
      Amount_Paid__c = 100,
      Special_Requests__c = 'quiet room'
    );
    insert f.booking;
    insert new PMS_Charge__c(
      Booking__c = f.booking.Id,
      Charge_Type__c = 'Room Night',
      Quantity__c = 1,
      Unit_Price__c = 100,
      Status__c = 'Invoiced'
    );
    insert new PMS_Invoice__c(
      Booking__c = f.booking.Id,
      Status__c = 'Paid',
      Subtotal__c = 100,
      Tax_Total__c = 0,
      Amount_Paid__c = 100
    );
    insert new PMS_Payment__c(
      Booking__c = f.booking.Id,
      Amount__c = 100,
      Method__c = 'Card',
      Payment_Type__c = 'Payment',
      Status__c = 'Succeeded'
    );
    insert new PMS_Check_In__c(
      Booking__c = f.booking.Id,
      Type__c = 'Hotel Stay',
      Full_Name__c = 'Eva Exported',
      ID_Number__c = 'P123'
    );
    insert new PMS_Guest_Preference__c(
      Contact__c = f.c.Id,
      Category__c = 'Room',
      Value__c = 'High floor'
    );
    insert new PMS_Intake_Form__c(
      Contact__c = f.c.Id,
      Form_Type__c = 'GDPR Consent',
      Responses__c = '{"a":1}',
      Consent_Given__c = true
    );
    insert new Case(
      ContactId = f.c.Id,
      Subject = 'Eva case',
      Description = 'desc'
    );

    Contact lead = PMS_TestDataFactory.contact(
      PMS_TestDataFactory.account('Lead acc').Id,
      'Lead'
    );
    f.partyBooking = new PMS_Booking__c(
      Primary_Contact__c = lead.Id,
      Status__c = 'Completed',
      Start__c = at(-30),
      End__c = at(-28),
      Total_Amount__c = 999,
      Amount_Paid__c = 999,
      Special_Requests__c = 'lead only request'
    );
    insert f.partyBooking;
    insert new PMS_Booking_Party__c(
      Booking__c = f.partyBooking.Id,
      Contact__c = f.c.Id,
      Role__c = 'Guest'
    );

    ContentVersion cv = new ContentVersion(
      Title = 'passport-scan',
      PathOnClient = 'passport-scan.txt',
      VersionData = Blob.valueOf('TOP-SECRET-FILE-BYTES'),
      // Links the file to the guest on insert. A separate ContentDocumentLink insert
      // intermittently failed with INVALID_CROSS_REFERENCE_KEY in parallel test runs.
      FirstPublishLocationId = f.c.Id
    );
    insert cv;
    f.docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id]
    .ContentDocumentId;
    return f;
  }

  private static Id user(
    String uniq,
    List<String> permSets,
    String profileName
  ) {
    Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
    User u;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      // avoids MIXED_DML after non-setup DML
      u = new User(
        Alias = uniq.left(8),
        Email = uniq + '@example.com',
        Username = uniq + '@pmsgdprc.example.com',
        LastName = uniq,
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        TimeZoneSidKey = 'America/Los_Angeles',
        ProfileId = p.Id
      );
      insert u;
      List<PermissionSetAssignment> psa = new List<PermissionSetAssignment>();
      for (PermissionSet ps : [
        SELECT Id
        FROM PermissionSet
        WHERE Name IN :permSets
      ]) {
        psa.add(
          new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = ps.Id
          )
        );
      }
      insert psa;
    }
    return u.Id;
  }

  private static Map<String, Object> parse(String json) {
    return (Map<String, Object>) System.JSON.deserializeUntyped(json);
  }

  @isTest
  static void canManageReflectsPermission() {
    PMS_GuestErasureService.permissionOverride = true;
    Assert.isTrue(PMS_GuestPrivacyController.canManage());
    PMS_GuestErasureService.permissionOverride = false;
    Assert.isFalse(PMS_GuestPrivacyController.canManage());
  }

  @isTest
  static void canManageRealUsers() {
    PMS_GuestErasureService.permissionOverride = null;
    Id admin = user(
      'gdprcadm',
      new List<String>{ 'PMS_Guest_Privacy_Admin' },
      'Standard User'
    );
    Id plain = user('gdprcpln', new List<String>(), 'Standard User');
    Test.startTest();
    System.runAs(new User(Id = admin)) {
      Assert.isTrue(PMS_GuestPrivacyController.canManage());
    }
    System.runAs(new User(Id = plain)) {
      Assert.isFalse(PMS_GuestPrivacyController.canManage());
    }
    Test.stopTest();
  }

  @isTest
  static void exportAndAnonymiseRequirePermission() {
    Fx f = fixture();
    PMS_GuestErasureService.permissionOverride = false;
    Test.startTest();
    try {
      PMS_GuestPrivacyController.exportGuestData(f.c.Id);
      Assert.fail('export should be denied');
    } catch (AuraHandledException e) {
      Assert.areEqual(
        'You do not have permission to manage guest privacy.',
        e.getMessage()
      );
    }
    try {
      PMS_GuestPrivacyController.anonymiseGuest(f.c.Id, 'reason');
      Assert.fail('anonymise should be denied');
    } catch (AuraHandledException e) {
      Assert.areEqual(
        'You do not have permission to manage guest privacy.',
        e.getMessage()
      );
    }
    Test.stopTest();
    Assert.isFalse(
      [SELECT PMS_Anonymised__c FROM Contact WHERE Id = :f.c.Id]
      .PMS_Anonymised__c
    );
  }

  /** Hands the sharing-controlled standard records (Account, Contact, Case) to the user so a with-sharing export can see them. PMS objects are public read/write internally. */
  private static void giveOwnership(Fx f, Id userId) {
    update new Account(Id = f.c.AccountId, OwnerId = userId);
    update new Contact(Id = f.c.Id, OwnerId = userId);
    List<Case> cs = [SELECT Id FROM Case WHERE ContactId = :f.c.Id];
    for (Case cs1 : cs) {
      cs1.OwnerId = userId;
    }
    update cs;
  }

  @isTest
  static void exportContainsAllSectionsAndNoFileContents() {
    Fx f = fixture();
    PMS_GuestErasureService.permissionOverride = null; // real custom permission check via the permission set
    // Standard User + permission set only (a System Administrator would mask missing grants in the set)
    Id admin = user(
      'gdprexp',
      new List<String>{ 'PMS_Guest_Privacy_Admin' },
      'Standard User'
    );
    giveOwnership(f, admin);
    String json;
    Test.startTest();
    System.runAs(new User(Id = admin)) {
      Assert.isTrue(
        PMS_GuestPrivacyController.canManage(),
        'admin holds PMS_Guest_Privacy'
      );
      json = PMS_GuestPrivacyController.exportGuestData(f.c.Id);
    }
    Test.stopTest();
    Map<String, Object> m = parse(json);
    for (String s : SECTIONS) {
      Assert.isTrue(m.containsKey(s), 'missing section ' + s);
    }
    Assert.areEqual(String.valueOf(f.c.Id), (String) m.get('contactId'));
    Assert.isFalse(
      json.contains('TOP-SECRET-FILE-BYTES'),
      'file contents must never be exported'
    );
    Assert.isFalse(json.contains('VersionData'));
    Assert.isTrue(json.contains('eva@example.com'));
    for (
      String related : new List<String>{
        'accounts',
        'bookingsAsPrimaryGuest',
        'bookingsAsPartyMember',
        'bookingParties',
        'charges',
        'invoices',
        'payments',
        'checkIns',
        'intakeForms',
        'cases'
      }
    ) {
      Assert.isFalse(
        ((List<Object>) m.get(related)).isEmpty(),
        related + ' must not be empty for the privacy admin'
      );
    }
    Assert.isTrue(json.contains('Eva case'), 'case content exported');
    Assert.isTrue(json.contains('P123'), 'check-in content exported');
    Assert.isTrue(
      json.contains('GDPR Consent'),
      'intake form content exported'
    );
    Assert.areEqual(1, ((List<Object>) m.get('preferences')).size());
    Assert.areEqual(1, ((List<Object>) m.get('bookingsAsPrimaryGuest')).size());
    Assert.areEqual(1, ((List<Object>) m.get('bookingsAsPartyMember')).size());
    Assert.areEqual(1, ((List<Object>) m.get('charges')).size());
    Assert.areEqual(1, ((List<Object>) m.get('invoices')).size());
    Assert.areEqual(1, ((List<Object>) m.get('payments')).size());
    Assert.areEqual(1, ((List<Object>) m.get('checkIns')).size());
    Assert.areEqual(1, ((List<Object>) m.get('intakeForms')).size());
    Assert.areEqual(1, ((List<Object>) m.get('cases')).size());
    Assert.areEqual(1, ((List<Object>) m.get('bookingParties')).size());
    List<Object> files = (List<Object>) m.get('fileNames');
    Assert.areEqual(1, files.size());
    Assert.areEqual(
      'passport-scan',
      (String) ((Map<String, Object>) files[0]).get('title')
    );
    // party-only booking: no amounts or special requests of the lead guest
    Assert.isFalse(json.contains('lead only request'));
    Map<String, Object> partyB = (Map<String, Object>) ((List<Object>) m.get(
      'bookingsAsPartyMember'
    ))[0];
    Assert.isFalse(partyB.containsKey('Total_Amount__c'));
    Assert.isFalse(partyB.containsKey('Special_Requests__c'));
    // custom field values present for the privacy admin
    Map<String, Object> cf = (Map<String, Object>) ((List<Object>) m.get(
      'contactCustomFields'
    ))[0];
    Assert.areEqual('Vegan', (String) cf.get('PMS_Dietary__c'));
  }

  @isTest
  static void exportRespectsFlsForRestrictedUser() {
    Fx f = fixture();
    // override grants the action; the user has no permission sets, so FLS strips what they cannot read
    Id restricted = user('gdprfls', new List<String>(), 'Standard User');
    Id admin = user(
      'gdprflsa',
      new List<String>{ 'PMS_Guest_Privacy_Admin' },
      'System Administrator'
    );
    update new Contact(Id = f.c.Id, OwnerId = restricted); // owner: sees the record, so only FLS differs
    String restrictedJson;
    String adminJson;
    Test.startTest();
    PMS_GuestErasureService.permissionOverride = true;
    Boolean restrictedExportFailed = false;
    System.runAs(new User(Id = restricted)) {
      try {
        restrictedJson = PMS_GuestPrivacyController.exportGuestData(f.c.Id);
      } catch (AuraHandledException e) {
        // a profile without read access to some PMS object makes stripInaccessible throw; also acceptable (nothing leaks)
        restrictedExportFailed = true;
        restrictedJson = '';
      }
    }
    System.runAs(new User(Id = admin)) {
      adminJson = PMS_GuestPrivacyController.exportGuestData(f.c.Id);
    }
    Test.stopTest();
    Assert.isTrue(
      adminJson.contains('vip secret'),
      'admin sees the VIP notes field'
    );
    Assert.isFalse(
      restrictedJson.contains('vip secret'),
      'FLS must strip PMS_VIP_Notes__c for the restricted user'
    );
    Assert.isTrue(
      restrictedExportFailed || restrictedJson.contains('Exported'),
      'either exported (stripped) or refused'
    );
    Assert.isFalse(restrictedJson.contains('TOP-SECRET-FILE-BYTES'));
  }

  @isTest
  static void exportRejectsNullAndUnknownContact() {
    PMS_GuestErasureService.permissionOverride = true;
    Test.startTest();
    try {
      PMS_GuestPrivacyController.exportGuestData(null);
      Assert.fail('null contact');
    } catch (AuraHandledException e) {
      Assert.areEqual('No guest selected.', e.getMessage());
    }
    Contact c = PMS_TestDataFactory.contact(null, 'Gone');
    Id gone = c.Id;
    delete c;
    try {
      PMS_GuestPrivacyController.exportGuestData(gone);
      Assert.fail('unknown contact');
    } catch (AuraHandledException e) {
      Assert.areEqual('Guest not found.', e.getMessage());
    }
    Test.stopTest();
  }

  @isTest
  static void anonymiseGuestReturnsSuccess() {
    Fx f = fixture();
    PMS_GuestErasureService.permissionOverride = true;
    Test.startTest();
    PMS_GuestErasureService.Result r = PMS_GuestPrivacyController.anonymiseGuest(
      f.c.Id,
      'Erasure request'
    );
    Test.stopTest();
    Assert.isTrue(r.success, r.message);
    Assert.areEqual('Guest anonymised.', r.message);
    Assert.isTrue(
      [SELECT PMS_Anonymised__c FROM Contact WHERE Id = :f.c.Id]
      .PMS_Anonymised__c
    );
  }

  @isTest
  static void anonymiseGuestReturnsBlockMessage() {
    Fx f = fixture();
    insert new PMS_Booking__c(
      Primary_Contact__c = f.c.Id,
      Status__c = 'Confirmed',
      Start__c = at(4),
      End__c = at(6)
    );
    PMS_GuestErasureService.permissionOverride = true;
    Test.startTest();
    PMS_GuestErasureService.Result r = PMS_GuestPrivacyController.anonymiseGuest(
      f.c.Id,
      'Erasure request'
    );
    Test.stopTest();
    Assert.isFalse(r.success);
    Assert.isTrue(r.blocked);
    Assert.areEqual(
      'The guest has an in-house or upcoming booking.',
      r.message
    );
    Assert.isFalse(
      [SELECT PMS_Anonymised__c FROM Contact WHERE Id = :f.c.Id]
      .PMS_Anonymised__c
    );
  }

  @isTest
  static void anonymiseGuestBlankReasonReturnsError() {
    Fx f = fixture();
    PMS_GuestErasureService.permissionOverride = true;
    Test.startTest();
    PMS_GuestErasureService.Result r = PMS_GuestPrivacyController.anonymiseGuest(
      f.c.Id,
      ' '
    );
    Test.stopTest();
    Assert.isFalse(r.success);
    Assert.areEqual('A reason is required.', r.message);
  }
}
