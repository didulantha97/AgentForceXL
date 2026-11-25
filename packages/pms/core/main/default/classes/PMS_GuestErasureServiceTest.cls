@isTest
private class PMS_GuestErasureServiceTest {
  private static final String REASON = 'Erasure request ref 42';

  /** Everything a fully populated, finished guest owns. */
  private class Fx {
    Account acc;
    Contact c;
    PMS_Booking__c booking;
    PMS_Check_In__c checkIn;
    PMS_Intake_Form__c gdprForm;
    PMS_Intake_Form__c healthForm;
    PMS_Guest_Preference__c pref;
    Case cs;
    CaseComment comment;
    PMS_Channel_Log__c log;
    PMS_Document_Request__c doc;
    PMS_Invoice__c invoice;
    PMS_Payment__c payment;
    PMS_Charge__c charge;
    Id fileDocId;
    Id sharedDocId;
    Account otherRecord;
  }

  private static Datetime at(Integer dayOffset) {
    return Datetime.newInstance(
      Date.today().addDays(dayOffset),
      Time.newInstance(12, 0, 0, 0)
    );
  }

  private static Id file(String title, Id linkedTo) {
    ContentVersion cv = new ContentVersion(
      Title = title,
      PathOnClient = title + '.txt',
      VersionData = Blob.valueOf('secret ' + title)
    );
    insert cv;
    Id docId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
    ]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      ContentDocumentId = docId,
      LinkedEntityId = linkedTo,
      ShareType = 'V'
    );
    return docId;
  }

  private static Account guestAccount(String name) {
    Account a = new Account(
      Name = name,
      PMS_Party_Role__c = 'Guest',
      PMS_Customer_Type__c = 'Consumer',
      Phone = '555-0100',
      Website = 'https://example.com',
      Description = 'private note',
      BillingStreet = '1 Main St',
      BillingCity = 'Town',
      ShippingStreet = '2 Side St',
      Stripe_Customer_Id__c = 'cus_123'
    );
    insert a;
    return a;
  }

  private static Contact fullContact(Id accountId, String last) {
    Contact c = new Contact(
      AccountId = accountId,
      Salutation = 'Ms.',
      FirstName = 'Ada',
      LastName = last,
      Title = 'CEO',
      Department = 'Ops',
      Email = last.toLowerCase() + '@example.com',
      Phone = '111',
      MobilePhone = '222',
      HomePhone = '333',
      OtherPhone = '444',
      Fax = '555',
      AssistantName = 'Asst',
      AssistantPhone = '666',
      Birthdate = Date.newInstance(1980, 1, 1),
      Description = 'likes cats',
      MailingStreet = 'M St',
      MailingCity = 'MC',
      MailingState = 'MS',
      MailingPostalCode = '123',
      MailingCountry = 'Sweden',
      OtherStreet = 'O St',
      OtherCity = 'OC',
      OtherState = 'OS',
      OtherPostalCode = '456',
      OtherCountry = 'Norway',
      HasOptedOutOfEmail = false,
      DoNotCall = false,
      PMS_Marketing_Consent__c = true,
      PMS_Consent_Date__c = Date.today(),
      PMS_Consent_Source__c = 'Web',
      PMS_ID_Verified__c = true,
      PMS_VIP_Notes__c = 'vip secret',
      PMS_Dietary__c = 'Vegan',
      PMS_Accessibility_Needs__c = 'Step free',
      PMS_Language__c = 'sv',
      PMS_OTA_Alias_Email__c = 'alias@guest.booking.com',
      PMS_Duplicate_Reason__c = 'same phone',
      PMS_Retention_Due__c = Date.today().addDays(-1),
      PMS_Total_Stays__c = 3,
      PMS_Lifetime_Nights__c = 9,
      PMS_Room_Revenue__c = 900,
      PMS_Extras_Revenue__c = 90
    );
    insert c;
    return c;
  }

  private static Fx fixture(String last) {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Fx f = new Fx();
    f.acc = guestAccount('Acc ' + last);
    f.c = fullContact(f.acc.Id, last);
    f.booking = new PMS_Booking__c(
      Primary_Contact__c = f.c.Id,
      Status__c = 'Completed',
      Start__c = at(-10),
      End__c = at(-7),
      Total_Amount__c = 100,
      Amount_Paid__c = 100,
      Special_Requests__c = 'quiet room',
      Web_Access_Key__c = 'webkey',
      Check_In_Key__c = 'ci-key',
      Card_Last4__c = '4242',
      Card_Expiry__c = '12/30',
      Stripe_Payment_Method__c = 'pm_123'
    );
    insert f.booking;
    f.charge = new PMS_Charge__c(
      Booking__c = f.booking.Id,
      Charge_Type__c = 'Room Night',
      Quantity__c = 1,
      Unit_Price__c = 100,
      Status__c = 'Invoiced'
    );
    insert f.charge;
    f.invoice = new PMS_Invoice__c(
      Booking__c = f.booking.Id,
      Status__c = 'Paid',
      Subtotal__c = 100,
      Tax_Total__c = 0,
      Amount_Paid__c = 100
    );
    insert f.invoice;
    f.payment = new PMS_Payment__c(
      Booking__c = f.booking.Id,
      Invoice__c = f.invoice.Id,
      Amount__c = 100,
      Method__c = 'Card',
      Payment_Type__c = 'Payment',
      Status__c = 'Succeeded',
      Gateway_Reference__c = 'pi_keep'
    );
    insert f.payment;
    // other writers may recalc these; pin them so the booking is financially settled
    update new PMS_Booking__c(
      Id = f.booking.Id,
      Total_Amount__c = 100,
      Amount_Paid__c = 100
    );

    f.checkIn = new PMS_Check_In__c(
      Booking__c = f.booking.Id,
      Type__c = 'Hotel Stay',
      Full_Name__c = 'Ada Lovelace',
      Address__c = '1 Main St',
      Date_Of_Birth__c = Date.newInstance(1980, 1, 1),
      Emergency_Contact__c = 'Bob 777',
      ID_Number__c = 'X123',
      ID_Type__c = 'Passport',
      Nationality__c = 'SE',
      Phone__c = '111',
      Special_Requests__c = 'late',
      Vehicle_Registration__c = 'ABC123',
      Arrival_Time__c = '15:00',
      Guests__c = 2,
      Terms_Accepted__c = true,
      Submitted_At__c = at(-11)
    );
    insert f.checkIn;
    f.gdprForm = new PMS_Intake_Form__c(
      Contact__c = f.c.Id,
      Form_Type__c = 'GDPR Consent',
      Responses__c = '{"name":"Ada"}',
      Signed_Date__c = Date.today().addDays(-30),
      Consent_Given__c = true
    );
    f.healthForm = new PMS_Intake_Form__c(
      Contact__c = f.c.Id,
      Form_Type__c = 'Health Questionnaire',
      Responses__c = '{"allergy":"nuts"}'
    );
    insert new List<PMS_Intake_Form__c>{ f.gdprForm, f.healthForm };
    f.pref = new PMS_Guest_Preference__c(
      Contact__c = f.c.Id,
      Category__c = 'Room',
      Value__c = 'High floor'
    );
    insert f.pref;
    f.cs = new Case(
      ContactId = f.c.Id,
      PMS_Booking__c = f.booking.Id,
      Subject = 'Ada complaint',
      Description = 'My phone is 111',
      SuppliedName = 'Ada',
      SuppliedEmail = 'ada@example.com',
      SuppliedPhone = '111',
      SuppliedCompany = 'ACME'
    );
    insert f.cs;
    f.comment = new CaseComment(ParentId = f.cs.Id, CommentBody = 'called Ada');
    insert f.comment;
    f.log = new PMS_Channel_Log__c(
      Booking__c = f.booking.Id,
      Details__c = '{"guest":"Ada"}',
      Message__c = 'Ada Lovelace booked'
    );
    insert f.log;
    f.doc = new PMS_Document_Request__c(
      Contact__c = f.c.Id,
      Title__c = 'Registration card',
      Status__c = 'Signed',
      Signer_Name__c = 'Ada Lovelace',
      Signer_Email__c = 'ada@example.com',
      Signer_IP__c = '1.2.3.4',
      Signer_User_Agent__c = 'Mozilla',
      Message__c = 'Dear Ada',
      Document_Hash__c = 'hash123'
    );
    insert f.doc;
    f.otherRecord = PMS_TestDataFactory.account('Other record');
    f.fileDocId = file('passport', f.c.Id);
    f.sharedDocId = file('shared', f.c.Id);
    insert new ContentDocumentLink(
      ContentDocumentId = f.sharedDocId,
      LinkedEntityId = f.otherRecord.Id,
      ShareType = 'V'
    );
    return f;
  }

  private static Contact reloadContact(Id id) {
    return [
      SELECT
        Salutation,
        FirstName,
        LastName,
        Title,
        Department,
        Email,
        Phone,
        MobilePhone,
        HomePhone,
        OtherPhone,
        Fax,
        AssistantName,
        AssistantPhone,
        Birthdate,
        Description,
        MailingStreet,
        MailingCity,
        MailingState,
        MailingPostalCode,
        MailingCountry,
        OtherStreet,
        OtherCity,
        OtherState,
        OtherPostalCode,
        OtherCountry,
        HasOptedOutOfEmail,
        DoNotCall,
        PMS_Do_Not_Contact__c,
        PMS_Marketing_Consent__c,
        PMS_Consent_Date__c,
        PMS_Consent_Source__c,
        PMS_ID_Verified__c,
        PMS_VIP_Level__c,
        PMS_VIP_Notes__c,
        PMS_Dietary__c,
        PMS_Accessibility_Needs__c,
        PMS_Language__c,
        PMS_OTA_Alias_Email__c,
        PMS_Possible_Duplicate_Of__c,
        PMS_Duplicate_Reason__c,
        PMS_Retention_Due__c,
        PMS_Anonymised__c,
        PMS_Anonymised_On__c,
        PMS_Anonymisation_Reason__c,
        PMS_Anonymised_By__c,
        PMS_Total_Stays__c,
        PMS_Lifetime_Nights__c,
        PMS_Room_Revenue__c,
        PMS_Extras_Revenue__c
      FROM Contact
      WHERE Id = :id
    ];
  }

  private static PMS_GuestErasureService.Result run(Id contactId) {
    PMS_GuestErasureService.permissionOverride = true;
    Test.startTest();
    PMS_GuestErasureService.Result r = PMS_GuestErasureService.anonymise(
      contactId,
      REASON
    );
    Test.stopTest();
    return r;
  }

  /** Nothing about the guest's data changed. */
  private static void assertUntouched(Fx f) {
    Contact c = reloadContact(f.c.Id);
    Assert.isFalse(c.PMS_Anonymised__c);
    Assert.areEqual('Ada', c.FirstName);
    Assert.areEqual(f.c.LastName, c.LastName);
    Assert.areEqual(f.c.Email, c.Email);
    Assert.areEqual('111', c.Phone);
    Assert.isNull(c.PMS_Anonymised_On__c);
    Assert.areEqual(
      'Acc ' + f.c.LastName,
      [SELECT Name FROM Account WHERE Id = :f.acc.Id].Name
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Guest_Preference__c WHERE Contact__c = :f.c.Id]
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM PMS_Intake_Form__c WHERE Contact__c = :f.c.Id]
    );
    PMS_Booking__c b = [
      SELECT Special_Requests__c, Card_Last4__c
      FROM PMS_Booking__c
      WHERE Id = :f.booking.Id
    ];
    Assert.areEqual('quiet room', b.Special_Requests__c);
    Assert.areEqual('4242', b.Card_Last4__c);
    Assert.areEqual(
      'Ada Lovelace',
      [SELECT Full_Name__c FROM PMS_Check_In__c WHERE Id = :f.checkIn.Id]
      .Full_Name__c
    );
    Assert.areEqual(
      'Ada complaint',
      [SELECT Subject FROM Case WHERE Id = :f.cs.Id].Subject
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM CaseComment WHERE ParentId = :f.cs.Id]
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :f.c.Id]
    );
  }

  private static void assertBlocked(Fx f, PMS_GuestErasureService.Result r) {
    Assert.isFalse(r.success);
    Assert.isTrue(r.blocked, 'expected blocked: ' + r.message);
    Assert.isNotNull(r.message);
    assertUntouched(f);
  }

  private static Id newUserWithPermissionSets(
    String uniq,
    List<String> permSets
  ) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    User u;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      // avoids MIXED_DML after non-setup DML
      u = new User(
        Alias = uniq.left(8),
        Email = uniq + '@example.com',
        Username = uniq + '@pmsgdpr.example.com',
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

  // ---------------------------------------------------------------- permission

  @isTest
  static void deniedWithoutPermissionOverride() {
    Fx f = fixture('NoPerm');
    PMS_GuestErasureService.permissionOverride = false;
    Test.startTest();
    PMS_GuestErasureService.Result r = PMS_GuestErasureService.anonymise(
      f.c.Id,
      REASON
    );
    Map<Id, PMS_GuestErasureService.Result> m = PMS_GuestErasureService.anonymise(
      new Set<Id>{ f.c.Id },
      REASON
    );
    Test.stopTest();
    Assert.isFalse(r.success);
    Assert.isFalse(r.blocked);
    Assert.areEqual(
      'You do not have permission to anonymise guests.',
      r.message
    );
    Assert.isFalse(m.get(f.c.Id).success);
    assertUntouched(f);
  }

  @isTest
  static void deniedForRealUserWithoutCustomPermission() {
    Fx f = fixture('RealDenied');
    Id uid = newUserWithPermissionSets('gdprnone', new List<String>());
    PMS_GuestErasureService.permissionOverride = null;
    PMS_GuestErasureService.Result r;
    Test.startTest();
    System.runAs(new User(Id = uid)) {
      Assert.isFalse(PMS_GuestErasureService.hasPermission());
      r = PMS_GuestErasureService.anonymise(f.c.Id, REASON);
    }
    Test.stopTest();
    Assert.isFalse(r.success);
    Assert.areEqual(
      'You do not have permission to anonymise guests.',
      r.message
    );
    assertUntouched(f);
  }

  @isTest
  static void realUserWithPrivacyAdminPermissionSetCanAnonymise() {
    Fx f = fixture('RealAdmin');
    Id uid = newUserWithPermissionSets(
      'gdprreal',
      new List<String>{ 'PMS_Guest_Privacy_Admin' }
    );
    PMS_GuestErasureService.permissionOverride = null; // prove the real FeatureManagement path
    PMS_GuestErasureService.Result r;
    Test.startTest();
    System.runAs(new User(Id = uid)) {
      Assert.isTrue(PMS_GuestErasureService.hasPermission());
      r = PMS_GuestErasureService.anonymise(f.c.Id, REASON);
    }
    Test.stopTest();
    Assert.isTrue(r.success, r.message);
    Contact c = reloadContact(f.c.Id);
    Assert.isTrue(c.PMS_Anonymised__c);
    Assert.areEqual(uid, c.PMS_Anonymised_By__c);
  }

  // ---------------------------------------------------------------- block rules

  @isTest
  static void blockedByUpcomingPrimaryBooking() {
    Fx f = fixture('UpPrimary');
    insert new PMS_Booking__c(
      Primary_Contact__c = f.c.Id,
      Status__c = 'Confirmed',
      Start__c = at(5),
      End__c = at(8)
    );
    assertBlocked(f, run(f.c.Id));
  }

  @isTest
  static void blockedByInHouseBooking() {
    Fx f = fixture('InHouse');
    insert new PMS_Booking__c(
      Primary_Contact__c = f.c.Id,
      Status__c = 'Active',
      Start__c = at(-1),
      End__c = at(2)
    );
    assertBlocked(f, run(f.c.Id));
  }

  @isTest
  static void blockedByUpcomingPartyBooking() {
    Fx f = fixture('UpParty');
    Contact other = PMS_TestDataFactory.contact(
      PMS_TestDataFactory.account('Lead acc').Id,
      'LeadGuest'
    );
    PMS_Booking__c b = new PMS_Booking__c(
      Primary_Contact__c = other.Id,
      Status__c = 'Tentative',
      Start__c = at(3),
      End__c = at(6)
    );
    insert b;
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = f.c.Id);
    assertBlocked(f, run(f.c.Id));
  }

  @isTest
  static void pastCancelledOrFutureCancelledBookingDoesNotBlock() {
    Fx f = fixture('Cancelled');
    insert new PMS_Booking__c(
      Primary_Contact__c = f.c.Id,
      Status__c = 'Cancelled',
      Start__c = at(5),
      End__c = at(8)
    );
    PMS_GuestErasureService.Result r = run(f.c.Id);
    Assert.isTrue(r.success, r.message);
  }

  @isTest
  static void blockedByBalanceDue() {
    Fx f = fixture('Balance');
    update new PMS_Booking__c(
      Id = f.booking.Id,
      Total_Amount__c = 150,
      Amount_Paid__c = 100
    );
    Assert.areEqual(
      50,
      [SELECT Balance_Due__c FROM PMS_Booking__c WHERE Id = :f.booking.Id]
      .Balance_Due__c,
      'precondition'
    );
    PMS_GuestErasureService.Result r = run(f.c.Id);
    assertBlocked(f, r);
    Assert.areEqual('The guest has an unpaid booking balance.', r.message);
  }

  @isTest
  static void blockedByRefundDue() {
    Fx f = fixture('Refund');
    update new PMS_Booking__c(Id = f.booking.Id, Refund_Due__c = 25);
    assertBlocked(f, run(f.c.Id));
  }

  @isTest
  static void blockedByOpenInvoiceWithBalance() {
    Fx f = fixture('OpenInv');
    // booking itself settled; only a second (inserted) invoice is open
    insert new PMS_Invoice__c(
      Booking__c = f.booking.Id,
      Status__c = 'Overdue',
      Subtotal__c = 100,
      Tax_Total__c = 0,
      Amount_Paid__c = 40
    );
    update new PMS_Booking__c(
      Id = f.booking.Id,
      Total_Amount__c = 100,
      Amount_Paid__c = 100
    );
    Assert.areEqual(
      0,
      [SELECT Balance_Due__c FROM PMS_Booking__c WHERE Id = :f.booking.Id]
      .Balance_Due__c,
      'precondition'
    );
    Assert.areEqual(
      60,
      [
        SELECT Balance__c
        FROM PMS_Invoice__c
        WHERE Status__c = 'Overdue' AND Booking__c = :f.booking.Id
      ]
      .Balance__c,
      'precondition'
    );
    PMS_GuestErasureService.Result r = run(f.c.Id);
    assertBlocked(f, r);
    Assert.areEqual('The guest has an unpaid invoice.', r.message);
  }

  @isTest
  static void blockedByOpenInvoiceOnPartyBooking() {
    Fx f = fixture('PartyInv');
    Contact lead = PMS_TestDataFactory.contact(
      PMS_TestDataFactory.account('Lead2').Id,
      'Lead2'
    );
    PMS_Booking__c b = new PMS_Booking__c(
      Primary_Contact__c = lead.Id,
      Status__c = 'Completed',
      Start__c = at(-20),
      End__c = at(-18)
    );
    insert b;
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = f.c.Id);
    insert new PMS_Invoice__c(
      Booking__c = b.Id,
      Status__c = 'Issued',
      Subtotal__c = 80,
      Tax_Total__c = 0,
      Amount_Paid__c = 0
    );
    update new PMS_Booking__c(
      Id = b.Id,
      Total_Amount__c = 0,
      Amount_Paid__c = 0
    );
    PMS_GuestErasureService.Result r = run(f.c.Id);
    assertBlocked(f, r);
  }

  @isTest
  static void paidAndVoidInvoicesDoNotBlock() {
    Fx f = fixture('PaidInv');
    insert new PMS_Invoice__c(
      Booking__c = f.booking.Id,
      Status__c = 'Void',
      Subtotal__c = 70,
      Tax_Total__c = 0,
      Amount_Paid__c = 0
    );
    PMS_GuestErasureService.Result r = run(f.c.Id);
    Assert.isTrue(r.success, r.message);
  }

  // ---------------------------------------------------------------- clean anonymise

  @isTest
  static void cleanAnonymiseBlanksPiiAndKeepsFinancialRecords() {
    Fx f = fixture('Clean');
    Integer charges = [
      SELECT COUNT()
      FROM PMS_Charge__c
      WHERE Booking__c = :f.booking.Id
    ];
    PMS_Invoice__c invBefore = [
      SELECT Status__c, Subtotal__c, Amount_Paid__c, Booking__c
      FROM PMS_Invoice__c
      WHERE Id = :f.invoice.Id
    ];
    PMS_GuestErasureService.Result r = run(f.c.Id);
    Assert.isTrue(r.success, r.message);
    Assert.isFalse(r.blocked);
    Assert.areEqual('Guest anonymised.', r.message);

    // Contact
    Contact c = reloadContact(f.c.Id);
    Assert.areEqual('Anonymised', c.FirstName);
    Assert.areEqual('Guest', c.LastName);
    Assert.isNull(c.Salutation);
    Assert.isNull(c.Title);
    Assert.isNull(c.Department);
    Assert.isNull(c.Email);
    Assert.isNull(c.Phone);
    Assert.isNull(c.MobilePhone);
    Assert.isNull(c.HomePhone);
    Assert.isNull(c.OtherPhone);
    Assert.isNull(c.Fax);
    Assert.isNull(c.AssistantName);
    Assert.isNull(c.AssistantPhone);
    Assert.isNull(c.Birthdate);
    Assert.isNull(c.Description);
    Assert.isNull(c.MailingStreet);
    Assert.isNull(c.MailingCity);
    Assert.isNull(c.MailingState);
    Assert.isNull(c.MailingPostalCode);
    Assert.isNull(c.MailingCountry);
    Assert.isNull(c.OtherStreet);
    Assert.isNull(c.OtherCity);
    Assert.isNull(c.OtherState);
    Assert.isNull(c.OtherPostalCode);
    Assert.isNull(c.OtherCountry);
    Assert.isTrue(c.HasOptedOutOfEmail);
    Assert.isTrue(c.DoNotCall);
    Assert.isTrue(c.PMS_Do_Not_Contact__c, 'suppression list kept');
    Assert.isFalse(c.PMS_Marketing_Consent__c);
    Assert.isNull(c.PMS_Consent_Date__c);
    Assert.isNull(c.PMS_Consent_Source__c);
    Assert.isFalse(c.PMS_ID_Verified__c);
    Assert.isNull(c.PMS_VIP_Level__c);
    Assert.isNull(c.PMS_VIP_Notes__c);
    Assert.isNull(c.PMS_Dietary__c);
    Assert.isNull(c.PMS_Accessibility_Needs__c);
    Assert.isNull(c.PMS_Language__c);
    Assert.isNull(c.PMS_OTA_Alias_Email__c);
    Assert.isNull(c.PMS_Possible_Duplicate_Of__c);
    Assert.isNull(c.PMS_Duplicate_Reason__c);
    Assert.isNull(c.PMS_Retention_Due__c);
    // audit
    Assert.isTrue(c.PMS_Anonymised__c);
    Assert.isNotNull(c.PMS_Anonymised_On__c);
    Assert.areEqual(REASON, c.PMS_Anonymisation_Reason__c);
    Assert.areEqual(UserInfo.getUserId(), c.PMS_Anonymised_By__c);
    // stats kept
    Assert.areEqual(3, c.PMS_Total_Stays__c);
    Assert.areEqual(9, c.PMS_Lifetime_Nights__c);
    Assert.areEqual(900, c.PMS_Room_Revenue__c);
    Assert.areEqual(90, c.PMS_Extras_Revenue__c);

    // Account
    Account a = [
      SELECT
        Name,
        Phone,
        Website,
        Description,
        BillingStreet,
        BillingCity,
        ShippingStreet,
        Stripe_Customer_Id__c
      FROM Account
      WHERE Id = :f.acc.Id
    ];
    Assert.areEqual('Anonymised Guest', a.Name);
    Assert.isNull(a.Phone);
    Assert.isNull(a.Website);
    Assert.isNull(a.Description);
    Assert.isNull(a.BillingStreet);
    Assert.isNull(a.BillingCity);
    Assert.isNull(a.ShippingStreet);
    Assert.isNull(a.Stripe_Customer_Id__c);

    // Preferences, forms
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Guest_Preference__c WHERE Contact__c = :f.c.Id]
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Intake_Form__c WHERE Id = :f.healthForm.Id],
      'non-GDPR form deleted'
    );
    PMS_Intake_Form__c g = [
      SELECT Responses__c, Form_Type__c, Signed_Date__c, Consent_Given__c
      FROM PMS_Intake_Form__c
      WHERE Id = :f.gdprForm.Id
    ];
    Assert.isNull(g.Responses__c);
    Assert.areEqual('GDPR Consent', g.Form_Type__c);
    Assert.areEqual(Date.today().addDays(-30), g.Signed_Date__c);
    Assert.isTrue(g.Consent_Given__c, 'consent evidence kept');

    // Check-in
    PMS_Check_In__c ci = [
      SELECT
        Full_Name__c,
        Address__c,
        Date_Of_Birth__c,
        Emergency_Contact__c,
        ID_Number__c,
        ID_Type__c,
        Nationality__c,
        Phone__c,
        Special_Requests__c,
        Vehicle_Registration__c,
        Arrival_Time__c,
        Guests__c,
        Terms_Accepted__c,
        Submitted_At__c,
        Type__c
      FROM PMS_Check_In__c
      WHERE Id = :f.checkIn.Id
    ];
    Assert.isNull(ci.Full_Name__c);
    Assert.isNull(ci.Address__c);
    Assert.isNull(ci.Date_Of_Birth__c);
    Assert.isNull(ci.Emergency_Contact__c);
    Assert.isNull(ci.ID_Number__c);
    Assert.isNull(ci.ID_Type__c);
    Assert.isNull(ci.Nationality__c);
    Assert.isNull(ci.Phone__c);
    Assert.isNull(ci.Special_Requests__c);
    Assert.isNull(ci.Vehicle_Registration__c);
    Assert.isNull(ci.Arrival_Time__c);
    Assert.areEqual(2, ci.Guests__c);
    Assert.isTrue(ci.Terms_Accepted__c);
    Assert.isNotNull(ci.Submitted_At__c);
    Assert.areEqual('Hotel Stay', ci.Type__c);

    // Booking
    PMS_Booking__c b = [
      SELECT
        Special_Requests__c,
        Web_Access_Key__c,
        Check_In_Key__c,
        Card_Last4__c,
        Card_Expiry__c,
        Stripe_Payment_Method__c,
        Status__c,
        Total_Amount__c,
        Amount_Paid__c,
        Primary_Contact__c
      FROM PMS_Booking__c
      WHERE Id = :f.booking.Id
    ];
    Assert.isNull(b.Special_Requests__c);
    Assert.isNull(b.Web_Access_Key__c);
    Assert.isNull(b.Check_In_Key__c);
    Assert.isNull(b.Card_Last4__c);
    Assert.isNull(b.Card_Expiry__c);
    Assert.isNull(b.Stripe_Payment_Method__c);
    Assert.areEqual('Completed', b.Status__c);
    Assert.areEqual(100, b.Total_Amount__c);
    Assert.areEqual(f.c.Id, b.Primary_Contact__c, 'booking link kept');

    // Case
    Case cs = [
      SELECT
        Subject,
        Description,
        SuppliedName,
        SuppliedEmail,
        SuppliedPhone,
        SuppliedCompany
      FROM Case
      WHERE Id = :f.cs.Id
    ];
    Assert.areEqual('Anonymised', cs.Subject);
    Assert.isNull(cs.Description);
    Assert.isNull(cs.SuppliedName);
    Assert.isNull(cs.SuppliedEmail);
    Assert.isNull(cs.SuppliedPhone);
    Assert.isNull(cs.SuppliedCompany);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM CaseComment WHERE ParentId = :f.cs.Id]
    );

    // Channel log, document request
    PMS_Channel_Log__c l = [
      SELECT Details__c, Message__c
      FROM PMS_Channel_Log__c
      WHERE Id = :f.log.Id
    ];
    Assert.isNull(l.Details__c);
    Assert.isNull(l.Message__c);
    PMS_Document_Request__c d = [
      SELECT
        Signer_Name__c,
        Signer_Email__c,
        Signer_IP__c,
        Signer_User_Agent__c,
        Message__c,
        Document_Hash__c,
        Status__c
      FROM PMS_Document_Request__c
      WHERE Id = :f.doc.Id
    ];
    Assert.areEqual('Anonymised', d.Signer_Name__c);
    Assert.isNull(d.Signer_Email__c);
    Assert.isNull(d.Signer_IP__c);
    Assert.isNull(d.Signer_User_Agent__c);
    Assert.isNull(d.Message__c);
    Assert.areEqual('hash123', d.Document_Hash__c, 'hash kept');
    Assert.areEqual('Signed', d.Status__c);

    // Files: private deleted, shared one unlinked only
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :f.fileDocId]
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :f.sharedDocId],
      'shared file survives'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM ContentDocumentLink
        WHERE ContentDocumentId = :f.sharedDocId AND LinkedEntityId = :f.c.Id
      ]
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM ContentDocumentLink
        WHERE
          ContentDocumentId = :f.sharedDocId
          AND LinkedEntityId = :f.otherRecord.Id
      ]
    );

    // Financial records untouched
    Assert.areEqual(
      charges,
      [SELECT COUNT() FROM PMS_Charge__c WHERE Booking__c = :f.booking.Id]
    );
    PMS_Invoice__c inv = [
      SELECT Status__c, Subtotal__c, Amount_Paid__c, Booking__c
      FROM PMS_Invoice__c
      WHERE Id = :f.invoice.Id
    ];
    Assert.areEqual(invBefore.Status__c, inv.Status__c);
    Assert.areEqual(invBefore.Subtotal__c, inv.Subtotal__c);
    Assert.areEqual(invBefore.Amount_Paid__c, inv.Amount_Paid__c);
    PMS_Payment__c p = [
      SELECT Amount__c, Status__c, Gateway_Reference__c
      FROM PMS_Payment__c
      WHERE Id = :f.payment.Id
    ];
    Assert.areEqual(100, p.Amount__c);
    Assert.areEqual('Succeeded', p.Status__c);
    Assert.areEqual('pi_keep', p.Gateway_Reference__c);
    Assert.isTrue(r.counts.get('Contacts anonymised') >= 1);
  }

  @isTest
  static void sharedAccountWithAnotherContactIsNotRenamed() {
    Fx f = fixture('SharedAcc');
    Contact sibling = PMS_TestDataFactory.contact(f.acc.Id, 'Sibling');
    Assert.isTrue(run(f.c.Id).success);
    Assert.areEqual(
      'Acc SharedAcc',
      [SELECT Name FROM Account WHERE Id = :f.acc.Id].Name
    );
    Assert.areEqual(
      'Sibling',
      [SELECT LastName FROM Contact WHERE Id = :sibling.Id].LastName
    );
  }

  @isTest
  static void businessAccountIsNotRenamed() {
    Fx f = fixture('BizAcc');
    update new Account(Id = f.acc.Id, PMS_Customer_Type__c = 'Business');
    Assert.isTrue(run(f.c.Id).success);
    Account a = [SELECT Name, Phone FROM Account WHERE Id = :f.acc.Id];
    Assert.areEqual('Acc BizAcc', a.Name);
    Assert.areEqual('555-0100', a.Phone);
  }

  @isTest
  static void accountWithMultipleRolesIsNotRenamed() {
    Fx f = fixture('MultiRole');
    update new Account(Id = f.acc.Id, PMS_Party_Role__c = 'Guest;Owner');
    Assert.isTrue(run(f.c.Id).success);
    Assert.areEqual(
      'Acc MultiRole',
      [SELECT Name FROM Account WHERE Id = :f.acc.Id].Name
    );
  }

  @isTest
  static void partyOnlyBookingDataIsUntouched() {
    Fx f = fixture('PartyOnly');
    Contact lead = PMS_TestDataFactory.contact(
      PMS_TestDataFactory.account('Lead3').Id,
      'Lead3'
    );
    PMS_Booking__c b = new PMS_Booking__c(
      Primary_Contact__c = lead.Id,
      Status__c = 'Completed',
      Start__c = at(-30),
      End__c = at(-28),
      Total_Amount__c = 0,
      Amount_Paid__c = 0,
      Special_Requests__c = 'lead request',
      Card_Last4__c = '1111'
    );
    insert b;
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = f.c.Id);
    PMS_Check_In__c leadCi = new PMS_Check_In__c(
      Booking__c = b.Id,
      Type__c = 'Hotel Stay',
      Full_Name__c = 'Lead Person',
      Phone__c = '999'
    );
    insert leadCi;
    PMS_Channel_Log__c leadLog = new PMS_Channel_Log__c(
      Booking__c = b.Id,
      Message__c = 'lead msg'
    );
    insert leadLog;
    Assert.isTrue(run(f.c.Id).success);
    PMS_Booking__c after = [
      SELECT Special_Requests__c, Card_Last4__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.areEqual('lead request', after.Special_Requests__c);
    Assert.areEqual('1111', after.Card_Last4__c);
    Assert.areEqual(
      'Lead Person',
      [SELECT Full_Name__c FROM PMS_Check_In__c WHERE Id = :leadCi.Id]
      .Full_Name__c
    );
    Assert.areEqual(
      'lead msg',
      [SELECT Message__c FROM PMS_Channel_Log__c WHERE Id = :leadLog.Id]
      .Message__c
    );
    Assert.areEqual(
      'Lead3',
      [SELECT LastName FROM Contact WHERE Id = :lead.Id].LastName
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Booking_Party__c
        WHERE Booking__c = :b.Id AND Contact__c = :f.c.Id
      ],
      'party link kept'
    );
  }

  @isTest
  static void guestWithNoRelatedDataIsAnonymised() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = PMS_TestDataFactory.contact(null, 'Lonely');
    PMS_GuestErasureService.Result r = run(c.Id);
    Assert.isTrue(r.success, r.message);
    Assert.isTrue(reloadContact(c.Id).PMS_Anonymised__c);
  }

  // ---------------------------------------------------------------- idempotence, validation

  @isTest
  static void secondCallIsIdempotent() {
    Fx f = fixture('Twice');
    PMS_GuestErasureService.permissionOverride = true;
    Test.startTest();
    Assert.isTrue(PMS_GuestErasureService.anonymise(f.c.Id, REASON).success);
    Contact first = reloadContact(f.c.Id);
    PMS_GuestErasureService.Result second = PMS_GuestErasureService.anonymise(
      f.c.Id,
      'Another reason'
    );
    Test.stopTest();
    Assert.isTrue(second.success);
    Assert.areEqual('Already anonymised. No changes made.', second.message);
    Contact after = reloadContact(f.c.Id);
    Assert.areEqual(
      REASON,
      after.PMS_Anonymisation_Reason__c,
      'original reason kept'
    );
    Assert.areEqual(first.PMS_Anonymised_On__c, after.PMS_Anonymised_On__c);
  }

  @isTest
  static void blankReasonIsRejected() {
    Fx f = fixture('NoReason');
    PMS_GuestErasureService.permissionOverride = true;
    Test.startTest();
    for (String reason : new List<String>{ null, '', '   ' }) {
      PMS_GuestErasureService.Result r = PMS_GuestErasureService.anonymise(
        f.c.Id,
        reason
      );
      Assert.isFalse(r.success);
      Assert.areEqual('A reason is required.', r.message);
    }
    Test.stopTest();
    assertUntouched(f);
  }

  @isTest
  static void nullContactAndUnknownContactAreRejected() {
    PMS_GuestErasureService.permissionOverride = true;
    Test.startTest();
    PMS_GuestErasureService.Result n = PMS_GuestErasureService.anonymise(
      (Id) null,
      REASON
    );
    Contact c = PMS_TestDataFactory.contact(null, 'Ghost');
    Id ghost = c.Id;
    delete c;
    PMS_GuestErasureService.Result g = PMS_GuestErasureService.anonymise(
      ghost,
      REASON
    );
    Map<Id, PMS_GuestErasureService.Result> empty = PMS_GuestErasureService.anonymise(
      new Set<Id>(),
      REASON
    );
    Test.stopTest();
    Assert.isFalse(n.success);
    Assert.areEqual('No guest selected.', n.message);
    Assert.isFalse(g.success);
    Assert.areEqual('Guest not found.', g.message);
    Assert.isTrue(empty.isEmpty());
  }

  @isTest
  static void longReasonIsTruncatedTo255() {
    Fx f = fixture('LongReason');
    PMS_GuestErasureService.permissionOverride = true;
    Test.startTest();
    PMS_GuestErasureService.Result r = PMS_GuestErasureService.anonymise(
      f.c.Id,
      '  ' + 'x'.repeat(400) + '  '
    );
    Test.stopTest();
    Assert.isTrue(r.success, r.message);
    Assert.areEqual(
      255,
      reloadContact(f.c.Id).PMS_Anonymisation_Reason__c.length()
    );
  }

  // ---------------------------------------------------------------- rollback

  @isTest
  static void failureMidwayRollsBackEverything() {
    Fx f = fixture('Rollback');
    PMS_GuestErasureService.permissionOverride = true;
    // Licence suspended: the Contact and Account updates succeed, then the Booking update is rejected by the
    // booking trigger licence guard. The service must roll the earlier DML back.
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    Test.startTest();
    PMS_GuestErasureService.Result r = PMS_GuestErasureService.anonymise(
      f.c.Id,
      REASON
    );
    Test.stopTest();
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Assert.isFalse(r.success);
    Assert.isFalse(r.blocked);
    Assert.isTrue(
      r.message.startsWith('Anonymisation failed and was rolled back'),
      r.message
    );
    assertUntouched(f);
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM PMS_Intake_Form__c WHERE Contact__c = :f.c.Id]
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :f.fileDocId]
    );
  }

  // ---------------------------------------------------------------- bulk

  @isTest
  static void bulkFiftyGuestsMixedBlockedAndClean() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    List<Account> accs = new List<Account>();
    for (Integer i = 0; i < 50; i++) {
      accs.add(
        new Account(
          Name = 'Bulk Acc ' + i,
          PMS_Party_Role__c = 'Guest',
          PMS_Customer_Type__c = 'Consumer'
        )
      );
    }
    insert accs;
    List<Contact> cs = new List<Contact>();
    for (Integer i = 0; i < 50; i++) {
      cs.add(
        new Contact(
          AccountId = accs[i].Id,
          FirstName = 'Bulk',
          LastName = 'G' + i,
          Email = 'g' + i + '@example.com',
          Phone = '12345'
        )
      );
    }
    insert cs;
    List<PMS_Booking__c> bs = new List<PMS_Booking__c>();
    for (Integer i = 0; i < 50; i++) {
      Boolean blocked = Math.mod(i, 2) == 0;
      bs.add(
        new PMS_Booking__c(
          Primary_Contact__c = cs[i].Id,
          Status__c = blocked ? 'Confirmed' : 'Completed',
          Start__c = at(blocked ? 4 : -9),
          End__c = at(blocked ? 6 : -7),
          Special_Requests__c = 'req ' + i
        )
      );
    }
    insert bs;
    Set<Id> ids = new Map<Id, Contact>(cs).keySet();
    PMS_GuestErasureService.permissionOverride = true;
    Test.startTest();
    Map<Id, PMS_GuestErasureService.Result> res = PMS_GuestErasureService.anonymise(
      ids,
      REASON
    );
    Test.stopTest();
    Assert.areEqual(50, res.size());
    for (Integer i = 0; i < 50; i++) {
      PMS_GuestErasureService.Result r = res.get(cs[i].Id);
      Contact c = [
        SELECT LastName, Email, PMS_Anonymised__c
        FROM Contact
        WHERE Id = :cs[i].Id
      ];
      if (Math.mod(i, 2) == 0) {
        Assert.isTrue(r.blocked, 'guest ' + i);
        Assert.isFalse(c.PMS_Anonymised__c);
        Assert.areEqual('G' + i, c.LastName);
      } else {
        Assert.isTrue(r.success, 'guest ' + i + ': ' + r.message);
        Assert.isTrue(c.PMS_Anonymised__c);
        Assert.isNull(c.Email);
      }
    }
    Assert.areEqual(
      25,
      [SELECT COUNT() FROM Contact WHERE PMS_Anonymised__c = TRUE]
    );
    Integer blankedBookings = 0;
    for (PMS_Booking__c b : [SELECT Special_Requests__c FROM PMS_Booking__c]) {
      if (b.Special_Requests__c == null) {
        blankedBookings++;
      }
    }
    Assert.areEqual(25, blankedBookings);
    Assert.areEqual(
      25,
      [SELECT COUNT() FROM Account WHERE Name = 'Anonymised Guest']
    );
  }

  @isTest
  static void trustedEntryPointSkipsPermissionCheck() {
    Fx f = fixture('Trusted');
    PMS_GuestErasureService.permissionOverride = false;
    Test.startTest();
    Map<Id, PMS_GuestErasureService.Result> res = PMS_GuestErasureService.anonymiseTrusted(
      new Set<Id>{ f.c.Id },
      REASON
    );
    Test.stopTest();
    Assert.isTrue(res.get(f.c.Id).success);
    Assert.isTrue(reloadContact(f.c.Id).PMS_Anonymised__c);
  }
}
