@isTest
private class PMS_PortalControllerTest {
  private class StripeMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setHeader('Content-Type', 'application/json');
      res.setBody(
        '{"id":"cs_test_1","url":"https://checkout.stripe.com/c/pay/cs_test_1","expires_at":1893456000}'
      );
      return res;
    }
  }

  private static User admin() {
    return [
      SELECT Id
      FROM User
      WHERE Username LIKE 'pms.portal.admin%'
      LIMIT 1
    ];
  }

  private static User portalUser() {
    return [
      SELECT Id, ContactId, Contact.AccountId
      FROM User
      WHERE Username LIKE 'pms.portal.customer%'
      LIMIT 1
    ];
  }

  @TestSetup
  static void setup() {
    UserRole role = new UserRole(
      Name = 'PMS Portal Test Role',
      DeveloperName = 'PMS_Portal_Test_Role'
    );
    insert role;
    Profile sysAdmin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    String stamp = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User adm = new User(
      ProfileId = sysAdmin.Id,
      UserRoleId = role.Id,
      FirstName = 'Portal',
      LastName = 'Admin',
      Alias = 'padm',
      Email = 'pms.portal.admin@example.com',
      Username = 'pms.portal.admin' + stamp + '@example.com',
      TimeZoneSidKey = 'Europe/Stockholm',
      LocaleSidKey = 'sv_SE',
      LanguageLocaleKey = 'en_US',
      EmailEncodingKey = 'UTF-8'
    );
    insert adm;

    Id contactId;
    System.runAs(adm) {
      PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
      Account other = PMS_TestDataFactory.account('Other Tenant AB');
      Contact c = PMS_TestDataFactory.contact(p.tenant.Id, 'Portaltenant');
      contactId = c.Id;

      Datetime startAt = Datetime.now().addDays(-30);
      PMS_Booking__c lease = new PMS_Booking__c(
        RecordTypeId = PMS_TestDataFactory.rt(
          PMS_Booking__c.SObjectType,
          'Lease'
        ),
        Site__c = p.site.Id,
        Space__c = p.unit.Id,
        Account__c = p.tenant.Id,
        Start__c = startAt,
        End__c = startAt.addDays(365),
        Status__c = 'Active'
      );
      insert lease;

      PMS_Invoice__c mine = new PMS_Invoice__c(
        Account__c = p.tenant.Id,
        Booking__c = lease.Id,
        Status__c = 'Issued',
        Issue_Date__c = Date.today().addDays(-20),
        Due_Date__c = Date.today().addDays(-5),
        Currency_Code__c = 'SEK'
      );
      PMS_Invoice__c theirs = new PMS_Invoice__c(
        Account__c = other.Id,
        Status__c = 'Issued',
        Issue_Date__c = Date.today(),
        Due_Date__c = Date.today().addDays(10),
        Currency_Code__c = 'SEK'
      );
      insert new List<PMS_Invoice__c>{ mine, theirs };
      insert new List<PMS_Charge__c>{
        new PMS_Charge__c(
          Invoice__c = mine.Id,
          Account__c = p.tenant.Id,
          Booking__c = lease.Id,
          Charge_Type__c = 'Rent',
          Description__c = 'Rent',
          Quantity__c = 1,
          Unit_Price__c = 9000,
          Tax_Rate__c = 0,
          Status__c = 'Invoiced',
          Service_Date__c = Date.today().addDays(-20)
        ),
        new PMS_Charge__c(
          Invoice__c = theirs.Id,
          Account__c = other.Id,
          Charge_Type__c = 'Rent',
          Description__c = 'Rent',
          Quantity__c = 1,
          Unit_Price__c = 5000,
          Tax_Rate__c = 0,
          Status__c = 'Invoiced',
          Service_Date__c = Date.today()
        )
      };
      insert new Case(
        Subject = 'Other tenant case',
        AccountId = other.Id,
        Status = 'New',
        Origin = 'Phone'
      );
      insert new PMS_Settings__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        Checkout_Return_URL__c = 'https://example.com/thanks'
      );
    }
    // Separate runAs block: the portal user (a setup object) can't share a DML context with the data above.
    System.runAs(adm) {
      List<Profile> portalProfiles = [
        SELECT Id
        FROM Profile
        WHERE Name = 'PMS Customer Portal User'
        LIMIT 1
      ];
      if (portalProfiles.isEmpty()) {
        portalProfiles = [
          SELECT Id
          FROM Profile
          WHERE UserLicense.Name = 'Customer Community Plus'
          LIMIT 1
        ];
      }
      insert new User(
        ProfileId = portalProfiles[0].Id,
        ContactId = contactId,
        FirstName = 'Pat',
        LastName = 'Portaltenant',
        Alias = 'ptnt',
        Email = 'portaltenant@example.com',
        Username = 'pms.portal.customer' + stamp + '@example.com',
        TimeZoneSidKey = 'Europe/Stockholm',
        LocaleSidKey = 'sv_SE',
        LanguageLocaleKey = 'en_US',
        EmailEncodingKey = 'UTF-8'
      );
    }
  }

  @isTest
  static void readsOnlyOwnRecords() {
    User u = portalUser();
    System.runAs(u) {
      Test.startTest();
      PMS_PortalController.Context ctx = PMS_PortalController.getContext();
      List<PMS_PortalController.BookingRow> bookings = PMS_PortalController.getBookings();
      List<PMS_PortalController.InvoiceRow> invoices = PMS_PortalController.getInvoices();
      List<PMS_PortalController.RequestRow> requests = PMS_PortalController.getRequests();
      Test.stopTest();

      Assert.areEqual('Pat', ctx.firstName);
      Assert.areEqual(1, ctx.activeBookings, 'active lease counted');
      Assert.areEqual(1, ctx.openInvoices, 'only own open invoice');
      Assert.areEqual(
        1,
        ctx.overdueInvoices,
        'past due date counts as overdue'
      );
      Assert.areEqual(1, bookings.size());
      Assert.areEqual('Lease', bookings[0].kind);
      Assert.areEqual(1, invoices.size(), 'other account invoice hidden');
      Assert.isTrue(invoices[0].payable);
      Assert.isTrue(invoices[0].balance > 0);
      Assert.areEqual(0, requests.size(), 'other account case hidden');
    }
  }

  @isTest
  static void createsRequestLinkedToBooking() {
    User u = portalUser();
    Id bookingId = [SELECT Id FROM PMS_Booking__c LIMIT 1].Id;
    System.runAs(u) {
      Test.startTest();
      String caseNumber = PMS_PortalController.createRequest(
        'Leaking tap',
        'Kitchen tap drips',
        bookingId,
        true
      );
      Test.stopTest();
      Assert.isNotNull(caseNumber);
      List<PMS_PortalController.RequestRow> requests = PMS_PortalController.getRequests();
      Assert.areEqual(1, requests.size());
      Assert.areEqual('Leaking tap', requests[0].subject);
      Assert.isTrue(requests[0].isOpen);
    }
    Case c = [
      SELECT
        AccountId,
        ContactId,
        PMS_Booking__c,
        PMS_Site__c,
        PMS_Module__c,
        Entry_Permission__c,
        Origin
      FROM Case
      WHERE Subject = 'Leaking tap'
    ];
    Assert.areEqual(u.Contact.AccountId, c.AccountId);
    Assert.areEqual(u.ContactId, c.ContactId);
    Assert.areEqual(bookingId, c.PMS_Booking__c);
    Assert.areEqual('Property', c.PMS_Module__c);
    Assert.isTrue(c.Entry_Permission__c);
    Assert.areEqual('Web', c.Origin);
  }

  @isTest
  static void rejectsBlankSubjectAndForeignRecords() {
    User u = portalUser();
    Id foreignInvoice = [
      SELECT Id
      FROM PMS_Invoice__c
      WHERE Account__r.Name = 'Other Tenant AB'
      LIMIT 1
    ]
    .Id;
    System.runAs(u) {
      Test.startTest();
      try {
        PMS_PortalController.createRequest('  ', null, null, false);
        Assert.fail('blank subject should fail');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('describe'));
      }
      try {
        PMS_PortalController.payInvoice(foreignInvoice);
        Assert.fail('foreign invoice should fail');
      } catch (AuraHandledException e) {
        Assert.areEqual('Invoice not found.', e.getMessage());
      }
      try {
        PMS_PortalController.createRequest(
          'Noise',
          null,
          foreignInvoice,
          false
        );
        Assert.fail('foreign id as booking should fail');
      } catch (AuraHandledException e) {
        Assert.areEqual('Booking not found.', e.getMessage());
      }
      Test.stopTest();
    }
  }

  @isTest
  static void paysOwnInvoiceThroughStripe() {
    User u = portalUser();
    Test.setMock(HttpCalloutMock.class, new StripeMock());
    System.runAs(u) {
      Id invoiceId = PMS_PortalController.getInvoices()[0].id;
      Test.startTest();
      PMS_PortalController.PayLink link = PMS_PortalController.payInvoice(
        invoiceId
      );
      Test.stopTest();
      Assert.areEqual('https://checkout.stripe.com/c/pay/cs_test_1', link.url);
      Assert.areEqual('SEK', link.currencyCode);
      Assert.isTrue(link.amount > 0);
    }
  }

  @isTest
  static void internalUserIsTurnedAway() {
    System.runAs(admin()) {
      try {
        PMS_PortalController.getContext();
        Assert.fail('internal user has no portal account');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('customer accounts'));
      }
    }
  }
}
