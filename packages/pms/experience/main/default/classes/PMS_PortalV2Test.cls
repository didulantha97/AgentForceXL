@isTest
private class PMS_PortalV2Test {
  private static final String PDF = EncodingUtil.base64Encode(
    Blob.valueOf('%PDF-1.4 lease agreement')
  );
  private static final String PNG = EncodingUtil.base64Encode(
    Blob.valueOf('fake-png-signature')
  );

  private static PMS_Booking__c hotelStay(
    PMS_ExperienceTestFactory.Hotel h,
    Integer daysAhead
  ) {
    PMS_BookingService.BookingRequest r = PMS_ExperienceTestFactory.hotelRequest(
      h,
      Date.today().addDays(daysAhead),
      2
    );
    r.status = 'Confirmed';
    return PMS_BookingService.createBooking(r);
  }

  private static void asCustomer(Id accountId, Id contactId) {
    PMS_PortalV2Controller.testAccountId = accountId;
    PMS_PortalV2Controller.testContactId = contactId;
  }

  // ------------------------------------------------------------------ check-in

  @isTest
  static void hotelGuestChecksInFromThePortal() {
    PMS_ExperienceTestFactory.Hotel h = PMS_ExperienceTestFactory.hotel(2);
    PMS_Booking__c b = hotelStay(h, 2);
    asCustomer(h.guestAccount.Id, h.guest.Id);

    PMS_PortalV2Controller.Home home = PMS_PortalV2Controller.getHome();
    Assert.areEqual(1, home.checkIns.size());
    PMS_CheckInService.Eligible e = home.checkIns[0];
    Assert.areEqual('hotel', e.kind);
    Assert.isFalse(e.done);
    Assert.areEqual(2, e.guests);
    Assert.areEqual(1, home.actionCount);

    try {
      PMS_PortalV2Controller.submitCheckIn(
        b.Id,
        JSON.serialize(
          new Map<String, Object>{
            'fullName' => 'Ann Guest',
            'arrivalTime' => '18:00'
          }
        )
      );
      Assert.fail('House rules must be accepted');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('house rules'), ex.getMessage());
    }
    List<PMS_CheckInService.Eligible> after = PMS_PortalV2Controller.submitCheckIn(
      b.Id,
      JSON.serialize(
        new Map<String, Object>{
          'fullName' => 'Ann Guest',
          'arrivalTime' => '18:00',
          'guests' => 2,
          'nationality' => 'Norway',
          'dateOfBirth' => '1990-04-01',
          'idType' => 'Passport',
          'idNumber' => 'N1234567',
          'requests' => 'Quiet room',
          'terms' => true
        }
      )
    );
    Assert.isTrue(after[0].done);
    PMS_Booking__c saved = [
      SELECT Online_Check_In__c, Special_Requests__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.isTrue(saved.Online_Check_In__c);
    Assert.isTrue(
      saved.Special_Requests__c.contains('arriving around 18:00'),
      saved.Special_Requests__c
    );
    PMS_Check_In__c ci = [
      SELECT Type__c, Nationality__c, ID_Type__c, Submitted_Via__c
      FROM PMS_Check_In__c
    ];
    Assert.areEqual('Hotel Stay', ci.Type__c);
    Assert.areEqual('Customer Portal', ci.Submitted_Via__c);

    try {
      PMS_PortalV2Controller.submitCheckIn(
        b.Id,
        JSON.serialize(
          new Map<String, Object>{
            'fullName' => 'x',
            'arrivalTime' => '1',
            'terms' => true
          }
        )
      );
      Assert.fail('Only once');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('already done'), ex.getMessage());
    }
    asCustomer(PMS_ExperienceTestFactory.account('Someone Else').Id, null);
    try {
      PMS_PortalV2Controller.submitCheckIn(b.Id, '{}');
      Assert.fail('Not their booking');
    } catch (AuraHandledException ex) {
      Assert.areEqual('Booking not found.', ex.getMessage());
    }
  }

  @isTest
  static void invitationLinkLetsAGuestCheckInWithoutLogin() {
    PMS_ExperienceTestFactory.Hotel h = PMS_ExperienceTestFactory.hotel(2);
    update new PMS_Site__c(Id = h.site.Id, Manager__c = UserInfo.getUserId());
    PMS_Booking__c b = hotelStay(h, 2);
    hotelStay(h, 10); // too far ahead to invite

    Assert.areEqual(1, PMS_CustomerNotifications.sendCheckInInvitations());
    Assert.areEqual(
      0,
      PMS_CustomerNotifications.sendCheckInInvitations(),
      'Invited once'
    );
    PMS_Booking__c invited = [
      SELECT Check_In_Key__c, Check_In_Invited_At__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.areEqual(64, invited.Check_In_Key__c.length());
    String body = PMS_CustomerNotifications.outbox[0].getPlainTextBody();
    Assert.isTrue(
      body.contains(
        '/book?checkin=' + b.Id + '&key=' + invited.Check_In_Key__c
      ),
      body
    );

    try {
      PMS_GuestCheckInController.getCheckIn(
        b.Id,
        invited.Check_In_Key__c.toUpperCase()
      );
      Assert.fail('The key is case-sensitive');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('not valid'), ex.getMessage());
    }
    PMS_GuestCheckInController.GuestView v = PMS_GuestCheckInController.getCheckIn(
      b.Id,
      invited.Check_In_Key__c
    );
    Assert.areEqual('hotel', v.checkIn.kind);
    v = PMS_GuestCheckInController.submitCheckIn(
      b.Id,
      invited.Check_In_Key__c,
      JSON.serialize(
        new Map<String, Object>{
          'fullName' => 'Ann Guest',
          'arrivalTime' => '22:30',
          'terms' => true
        }
      )
    );
    Assert.isTrue(v.checkIn.done);
    Assert.areEqual(
      'Email Link',
      [SELECT Submitted_Via__c FROM PMS_Check_In__c].Submitted_Via__c
    );
    Assert.isTrue(
      PMS_CustomerNotifications.outbox.size() >= 2,
      'Site manager alerted'
    );
    new PMS_CheckInInvitationJob().execute(null);
  }

  @isTest
  static void patientFillsInTheHealthQuestionnaire() {
    PMS_ExperienceTestFactory.Practice p = PMS_ExperienceTestFactory.practice();
    update new PMS_Site__c(
      Id = p.site.Id,
      Time_Zone__c = 'Europe/Stockholm',
      Currency_Code__c = 'SEK'
    );
    Contact client = PMS_ExperienceTestFactory.contact(p.client.Id, 'Patient');
    PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
    r.module = PMS_ModuleConfig.PRACTICE;
    r.siteId = p.site.Id;
    r.serviceId = p.service.Id;
    r.practitionerId = p.practitioner.Id;
    r.startDatetime = PMS_DateUtil.toDatetime(
      PMS_ExperienceTestFactory.futureMonday(),
      Time.newInstance(10, 0, 0, 0),
      'Europe/Stockholm'
    );
    r.accountId = p.client.Id;
    r.contactId = client.Id;
    r.adults = 1;
    r.status = 'Confirmed';
    PMS_Booking__c b = PMS_BookingService.createBooking(r);
    String key = PMS_CheckInService.newKey();
    update new PMS_Booking__c(Id = b.Id, Check_In_Key__c = key);

    PMS_GuestCheckInController.GuestView v = PMS_GuestCheckInController.getCheckIn(
      b.Id,
      key
    );
    Assert.areEqual('clinic', v.checkIn.kind);
    Assert.areEqual(
      PMS_CheckInService.CLINIC_QUESTIONS.size(),
      v.checkIn.questions.size()
    );
    try {
      PMS_GuestCheckInController.submitCheckIn(
        b.Id,
        key,
        JSON.serialize(new Map<String, Object>{ 'consentTreatment' => true })
      );
      Assert.fail('The reason is required');
    } catch (AuraHandledException ex) {
      Assert.isTrue(
        ex.getMessage().startsWith('Please answer'),
        ex.getMessage()
      );
    }
    v = PMS_GuestCheckInController.submitCheckIn(
      b.Id,
      key,
      JSON.serialize(
        new Map<String, Object>{
          'answers' => new Map<String, String>{
            'reason' => 'Sore lower back for 3 weeks',
            'pain' => '6'
          },
          'consentTreatment' => true,
          'consentData' => true
        }
      )
    );
    Assert.isTrue(v.checkIn.done);
    PMS_Intake_Form__c f = [
      SELECT Form_Type__c, Responses__c, Consent_Given__c, Contact__c
      FROM PMS_Intake_Form__c
      WHERE Booking__c = :b.Id
    ];
    Assert.areEqual('Health Questionnaire', f.Form_Type__c);
    Assert.areEqual(client.Id, f.Contact__c);
    Assert.isTrue(f.Responses__c.contains('Sore lower back'));
  }

  @isTest
  static void tenantSendsMoveInDetailsAndMeterReadings() {
    PMS_ExperienceTestFactory.Property p = PMS_ExperienceTestFactory.property();
    PMS_Meter__c meter = new PMS_Meter__c(
      Name = 'Electricity A-101',
      Space__c = p.unit.Id
    );
    insert meter;
    PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
    r.module = 'Property';
    r.siteId = p.site.Id;
    r.spaceId = p.unit.Id;
    r.accountId = p.tenant.Id;
    r.startDate = Date.today().addDays(10);
    r.endDate = Date.today().addMonths(12);
    r.status = 'Confirmed';
    PMS_Booking__c lease = PMS_BookingService.createBooking(r);
    asCustomer(p.tenant.Id, null);

    PMS_CheckInService.Eligible e = PMS_PortalV2Controller.getHome()
      .checkIns[0];
    Assert.areEqual('movein', e.kind);
    Assert.areEqual(1, e.meters.size());
    try {
      PMS_PortalV2Controller.submitCheckIn(
        lease.Id,
        JSON.serialize(
          new Map<String, Object>{
            'fullName' => 'T Tenant',
            'terms' => true,
            'readings' => new List<Object>{
              new Map<String, Object>{ 'meterId' => meter.Id, 'value' => -1 }
            }
          }
        )
      );
      Assert.fail('Negative reading');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('negative'), ex.getMessage());
    }
    PMS_PortalV2Controller.submitCheckIn(
      lease.Id,
      JSON.serialize(
        new Map<String, Object>{
          'fullName' => 'T Tenant',
          'terms' => true,
          'occupants' => 2,
          'moveInDate' => String.valueOf(Date.today().addDays(10)),
          'readings' => new List<Object>{
            new Map<String, Object>{ 'meterId' => meter.Id, 'value' => 10234.5 }
          }
        }
      )
    );
    PMS_Meter_Reading__c reading = [
      SELECT Reading_Value__c, Reading_Date__c
      FROM PMS_Meter_Reading__c
      WHERE Meter__c = :meter.Id
    ];
    PMS_ExperienceTestFactory.num(
      10234.5,
      reading.Reading_Value__c,
      'meter reading'
    );
    Assert.areEqual(Date.today().addDays(10), reading.Reading_Date__c);
    Assert.areEqual(
      'Move-In',
      [SELECT Type__c FROM PMS_Check_In__c WHERE Booking__c = :lease.Id LIMIT 1]
      .Type__c
    );
  }

  // ------------------------------------------------------------------ e-signature

  private static PMS_Document_Request__c documentFor(
    Account a,
    Contact c,
    Boolean sign
  ) {
    PMS_Document_Request__c d = new PMS_Document_Request__c(
      Title__c = 'Lease agreement A-101',
      Account__c = a.Id,
      Contact__c = c.Id,
      Requires_Signature__c = sign,
      Status__c = 'Draft',
      Message__c = 'Please sign by Friday.'
    );
    insert d;
    insert new ContentVersion(
      Title = 'Lease A-101',
      PathOnClient = 'Lease A-101.pdf',
      VersionData = EncodingUtil.base64Decode(PDF),
      FirstPublishLocationId = d.Id
    );
    d.Status__c = 'Sent';
    update d;
    return d;
  }

  @isTest
  static void customerSignsADocument() {
    Account a = PMS_ExperienceTestFactory.account('Signer AB');
    Contact c = PMS_ExperienceTestFactory.contact(a.Id, 'Signer');
    update new PMS_Document_Request__c(
      Id = documentFor(a, c, true).Id,
      OwnerId = UserInfo.getUserId()
    );
    PMS_Document_Request__c d = [SELECT Id FROM PMS_Document_Request__c];
    Assert.isTrue(
      PMS_CustomerNotifications.outbox[0]
        .getSubject()
        .startsWith('Please sign:'),
      'The signer was emailed'
    );
    asCustomer(a.Id, c.Id);

    PMS_PortalV2Controller.Home home = PMS_PortalV2Controller.getHome();
    Assert.areEqual(1, home.documents.size());
    Assert.isTrue(home.documents[0].canSign);
    Assert.isTrue(home.documents[0].isPdf);

    PMS_PortalV2Controller.FileData f = PMS_PortalV2Controller.getDocument(
      d.Id
    );
    Assert.areEqual(PDF, f.base64);
    Assert.areEqual(
      'Viewed',
      [SELECT Status__c FROM PMS_Document_Request__c].Status__c
    );

    try {
      PMS_PortalV2Controller.signDocument(
        d.Id,
        'Sam Signer',
        PNG,
        'Test browser',
        false
      );
      Assert.fail('Consent is required');
    } catch (AuraHandledException ex) {
      Assert.isTrue(
        ex.getMessage().contains('electronic signature'),
        ex.getMessage()
      );
    }
    PMS_PortalV2Controller.SignResult s = PMS_PortalV2Controller.signDocument(
      d.Id,
      '  Sam   Signer ',
      PNG,
      'Test browser',
      true
    );
    Assert.areEqual('Sam Signer', s.signerName);
    String expectedHash = EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', EncodingUtil.base64Decode(PDF))
    );
    Assert.areEqual(expectedHash, s.documentHash);
    PMS_Document_Request__c signed = [
      SELECT Status__c, Signed_At__c, Document_Hash__c, Signer_User_Agent__c
      FROM PMS_Document_Request__c
    ];
    Assert.areEqual('Signed', signed.Status__c);
    Assert.areEqual(expectedHash, signed.Document_Hash__c);
    Assert.isNotNull(signed.Signed_At__c);

    try {
      PMS_PortalV2Controller.attachSignedPdf(d.Id, PNG);
      Assert.fail('Must be a PDF');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('not a PDF'), ex.getMessage());
    }
    PMS_PortalV2Controller.DocRow row = PMS_PortalV2Controller.attachSignedPdf(
      d.Id,
      'data:application/pdf;base64,' +
      EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 signed copy'))
    );
    Assert.isTrue(row.hasSignedCopy);
    Assert.isFalse(row.canSign);
    Assert.isTrue(
      PMS_PortalV2Controller.getSignedDocument(d.Id).fileName.contains('signed')
    );
    Assert.areEqual(
      PDF,
      PMS_PortalV2Controller.getDocument(d.Id).base64,
      'The original is still served'
    );
    try {
      PMS_PortalV2Controller.attachSignedPdf(
        d.Id,
        EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 again'))
      );
      Assert.fail('Only one signed copy');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('already filed'), ex.getMessage());
    }
    try {
      PMS_PortalV2Controller.signDocument(
        d.Id,
        'Sam Signer',
        PNG,
        'Test',
        true
      );
      Assert.fail('Signed only once');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('no longer'), ex.getMessage());
    }
  }

  @isTest
  static void customerDeclinesAndOthersSeeNothing() {
    Account a = PMS_ExperienceTestFactory.account('Decliner AB');
    Contact c = PMS_ExperienceTestFactory.contact(a.Id, 'Decliner');
    PMS_Document_Request__c d = documentFor(a, c, true);
    asCustomer(PMS_ExperienceTestFactory.account('Stranger').Id, null);
    Assert.areEqual(0, PMS_PortalV2Controller.getHome().documents.size());
    try {
      PMS_PortalV2Controller.getDocument(d.Id);
      Assert.fail('Not theirs');
    } catch (AuraHandledException ex) {
      Assert.areEqual('Document not found.', ex.getMessage());
    }
    asCustomer(a.Id, c.Id);
    try {
      PMS_PortalV2Controller.declineDocument(d.Id, ' ');
      Assert.fail('Reason required');
    } catch (AuraHandledException ex) {
      Assert.isNotNull(ex.getMessage());
    }
    PMS_PortalV2Controller.declineDocument(d.Id, 'The rent amount is wrong.');
    Assert.areEqual(
      'Declined',
      [SELECT Status__c FROM PMS_Document_Request__c].Status__c
    );
    try {
      PMS_PortalV2Controller.getSignedDocument(d.Id);
      Assert.fail('No signed copy');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('not ready'), ex.getMessage());
    }
    PMS_PortalV2Controller.testAccountId = null;
    try {
      PMS_PortalV2Controller.getHome();
      Assert.fail('Internal users have no customer account');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('portal login'), ex.getMessage());
    }
  }

  // ------------------------------------------------------------------ projects

  @isTest
  static void customerAcceptsMilestonesAndDecidesChangeOrders() {
    PMS_Project__c proj = PMS_ExperienceTestFactory.projectWithTasks();
    proj = [SELECT Id, Account__c FROM PMS_Project__c WHERE Id = :proj.Id];
    Contact c = PMS_ExperienceTestFactory.contact(proj.Account__c, 'Client');
    PMS_Milestone__c m = [
      SELECT Id
      FROM PMS_Milestone__c
      WHERE Project__c = :proj.Id
      LIMIT 1
    ];
    m.Status__c = 'Completed';
    update m;
    PMS_Approval_Request__c ar = new PMS_Approval_Request__c(
      Project__c = proj.Id,
      Title__c = 'Upgrade to oak flooring',
      Type__c = 'Change Order',
      Amount__c = 42000,
      Status__c = 'Pending'
    );
    insert ar;
    Assert.areEqual(
      proj.Account__c,
      [SELECT Account__c FROM PMS_Approval_Request__c].Account__c,
      'Account filled from the project'
    );
    asCustomer(proj.Account__c, c.Id);

    PMS_PortalV2Controller.Home home = PMS_PortalV2Controller.getHome();
    Assert.areEqual(1, home.projects.size());
    Assert.isTrue(home.projects[0].milestones[0].canAccept);
    Assert.isTrue(home.projects[0].approvals[0].canDecide);
    Assert.areEqual(2, home.actionCount);

    PMS_PortalV2Controller.queryMilestone(
      m.Id,
      'The meeting room door is still missing.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Case
        WHERE Subject LIKE 'Milestone query:%' AND ContactId = :c.Id
      ]
    );
    List<PMS_PortalV2Controller.ProjectRow> rows = PMS_PortalV2Controller.acceptMilestone(
      m.Id,
      'Looks great'
    );
    PMS_Milestone__c accepted = [
      SELECT Status__c, Accepted_By__c, Customer_Comment__c
      FROM PMS_Milestone__c
      WHERE Id = :m.Id
    ];
    Assert.areEqual('Accepted', accepted.Status__c);
    Assert.areEqual(c.Id, accepted.Accepted_By__c);
    try {
      PMS_PortalV2Controller.acceptMilestone(m.Id, null);
      Assert.fail('Already accepted');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('completed'), ex.getMessage());
    }

    try {
      PMS_PortalV2Controller.decideApproval(ar.Id, false, '');
      Assert.fail('Rejection needs a reason');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('why'), ex.getMessage());
    }
    rows = PMS_PortalV2Controller.decideApproval(ar.Id, true, 'Go ahead');
    PMS_Approval_Request__c decided = [
      SELECT Status__c, Decided_By__c, Decided_At__c
      FROM PMS_Approval_Request__c
    ];
    Assert.areEqual('Approved', decided.Status__c);
    Assert.areEqual(c.Id, decided.Decided_By__c);
    try {
      PMS_PortalV2Controller.decideApproval(ar.Id, true, null);
      Assert.fail('Decided once');
    } catch (AuraHandledException ex) {
      Assert.isTrue(ex.getMessage().contains('already'), ex.getMessage());
    }
  }

  @isTest
  static void portalUsersGetBothCustomerPermissionSets() {
    List<String> sets = PMS_PortalUserSetup.PERMSETS_BY_PROFILE.get(
      PMS_PortalUserSetup.PORTAL_PROFILE
    );
    Assert.isTrue(sets.contains(PMS_PortalUserSetup.STRIPE_PERMSET));
    Assert.isTrue(sets.contains(PMS_PortalUserSetup.CUSTOMER_PERMSET));
    Assert.areEqual(
      PMS_PortalUserSetup.PARTNER_PERMSET,
      PMS_PortalUserSetup.PERMSET_BY_PROFILE.get(
        PMS_PortalUserSetup.PARTNER_PROFILE
      )
    );
    PMS_PortalUserSetup.assign(new Set<Id>{ UserInfo.getUserId() });
    Assert.isTrue(
      PMS_CustomerNotifications.siteUrl('No Such Network', '/book')
        .endsWith('/book')
    );
  }
}
