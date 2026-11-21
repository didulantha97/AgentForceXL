@isTest
private class PMS_PortalMoneyControllerTest {
  private static User portalUser() {
    return [
      SELECT Id, ContactId, Contact.AccountId
      FROM User
      WHERE Username LIKE 'pms.moneyportal.customer%'
      LIMIT 1
    ];
  }

  private static User admin() {
    return [
      SELECT Id
      FROM User
      WHERE Username LIKE 'pms.moneyportal.admin%'
      LIMIT 1
    ];
  }

  @TestSetup
  static void setup() {
    UserRole role = new UserRole(
      Name = 'PMS Money Portal Test Role',
      DeveloperName = 'PMS_Money_Portal_Test_Role'
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
      Alias = 'mpadm',
      Email = 'pms.moneyportal.admin@example.com',
      Username = 'pms.moneyportal.admin' + stamp + '@example.com',
      TimeZoneSidKey = 'Europe/Stockholm',
      LocaleSidKey = 'sv_SE',
      LanguageLocaleKey = 'en_US',
      EmailEncodingKey = 'UTF-8'
    );
    insert adm;

    Id contactId;
    System.runAs(adm) {
      PMS_ExperienceTestFactory.Property p = PMS_ExperienceTestFactory.property();
      PMS_ExperienceTestFactory.Hotel h = PMS_ExperienceTestFactory.hotel(1);
      Account other = PMS_ExperienceTestFactory.account('Other Tenant AB');
      Contact c = PMS_ExperienceTestFactory.contact(p.tenant.Id, 'Moneytenant');
      contactId = c.Id;

      Datetime startAt = Datetime.now().addDays(-30);
      PMS_Booking__c lease = new PMS_Booking__c(
        RecordTypeId = PMS_ExperienceTestFactory.rt(
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
      // The property's site bills in NOK, which differs from the org default.
      update new PMS_Site__c(Id = p.site.Id, Currency_Code__c = 'NOK');

      Date today = Date.today();
      PMS_Invoice__c overdue = new PMS_Invoice__c(
        Account__c = p.tenant.Id,
        Booking__c = lease.Id,
        Status__c = 'Issued',
        Issue_Date__c = today.addDays(-20),
        Due_Date__c = today.addDays(-5),
        Currency_Code__c = 'SEK',
        Dunning_Stage__c = 'Reminder 1',
        Pay_Key__c = 'key with/space'
      );
      PMS_Invoice__c upcoming = new PMS_Invoice__c(
        Account__c = p.tenant.Id,
        Status__c = 'Issued',
        Issue_Date__c = today,
        Due_Date__c = today.addDays(10),
        Currency_Code__c = 'SEK'
      );
      PMS_Invoice__c draft = new PMS_Invoice__c(
        Account__c = p.tenant.Id,
        Status__c = 'Draft',
        Issue_Date__c = today,
        Due_Date__c = today.addDays(10),
        Currency_Code__c = 'SEK'
      );
      PMS_Invoice__c theirs = new PMS_Invoice__c(
        Account__c = other.Id,
        Status__c = 'Issued',
        Issue_Date__c = today,
        Due_Date__c = today.addDays(10),
        Currency_Code__c = 'SEK'
      );
      insert new List<PMS_Invoice__c>{ overdue, upcoming, draft, theirs };
      List<PMS_Charge__c> charges = new List<PMS_Charge__c>();
      for (
        PMS_Invoice__c inv : new List<PMS_Invoice__c>{
          overdue,
          upcoming,
          draft,
          theirs
        }
      ) {
        charges.add(
          new PMS_Charge__c(
            Invoice__c = inv.Id,
            Account__c = inv.Account__c,
            Charge_Type__c = 'Other',
            Description__c = 'Charge',
            Quantity__c = 1,
            Unit_Price__c = inv.Id == overdue.Id ? 9000 : 100,
            Tax_Rate__c = 0,
            Status__c = 'Invoiced'
          )
        );
      }
      insert charges;

      PMS_Payment_Plan__c active = new PMS_Payment_Plan__c(
        Invoice__c = overdue.Id,
        Account__c = p.tenant.Id,
        Status__c = 'Active'
      );
      PMS_Payment_Plan__c cancelled = new PMS_Payment_Plan__c(
        Invoice__c = upcoming.Id,
        Account__c = p.tenant.Id,
        Status__c = 'Cancelled'
      );
      insert new List<PMS_Payment_Plan__c>{ active, cancelled };
      insert new List<PMS_Payment_Plan_Instalment__c>{
        new PMS_Payment_Plan_Instalment__c(
          Plan__c = active.Id,
          Number__c = 1,
          Due_Date__c = today.addDays(-3),
          Amount__c = 4500,
          Status__c = 'Overdue'
        ),
        new PMS_Payment_Plan_Instalment__c(
          Plan__c = active.Id,
          Number__c = 2,
          Due_Date__c = today.addDays(20),
          Amount__c = 4500,
          Status__c = 'Due'
        ),
        new PMS_Payment_Plan_Instalment__c(
          Plan__c = cancelled.Id,
          Number__c = 1,
          Due_Date__c = today.addDays(5),
          Amount__c = 100,
          Status__c = 'Due'
        )
      };

      Id resRt = PMS_ExperienceTestFactory.rt(
        PMS_Booking__c.SObjectType,
        'Reservation'
      );
      insert new List<PMS_Booking__c>{
        new PMS_Booking__c(
          RecordTypeId = resRt,
          Site__c = h.site.Id,
          Space__c = h.rooms[0].Id,
          Account__c = p.tenant.Id,
          Status__c = 'Confirmed',
          Start__c = Datetime.now().addDays(10),
          End__c = Datetime.now().addDays(12),
          Guarantee_Status__c = 'Awaiting Card'
        ),
        new PMS_Booking__c(
          RecordTypeId = resRt,
          Site__c = h.site.Id,
          Space__c = h.rooms[0].Id,
          Account__c = p.tenant.Id,
          Status__c = 'Cancelled',
          Start__c = Datetime.now().addDays(20),
          End__c = Datetime.now().addDays(22),
          Guarantee_Status__c = 'Awaiting Card'
        )
      };

      insert new List<PMS_Rent_Adjustment__c>{
        new PMS_Rent_Adjustment__c(
          Lease__c = lease.Id,
          Status__c = 'Notice Sent',
          Kind__c = 'Index',
          Effective_Date__c = today.addDays(-10),
          Old_Rent__c = 9000,
          New_Rent__c = 9270
        ),
        new PMS_Rent_Adjustment__c(
          Lease__c = lease.Id,
          Status__c = 'Draft',
          Kind__c = 'Index',
          Effective_Date__c = today.addDays(30)
        ),
        new PMS_Rent_Adjustment__c(
          Lease__c = lease.Id,
          Status__c = 'Applied',
          Kind__c = 'Index',
          Effective_Date__c = today.addDays(-400),
          Old_Rent__c = 8000,
          New_Rent__c = 8500
        )
      };
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
        LastName = 'Moneytenant',
        Alias = 'mptnt',
        Email = 'moneytenant@example.com',
        Username = 'pms.moneyportal.customer' + stamp + '@example.com',
        TimeZoneSidKey = 'Europe/Stockholm',
        LocaleSidKey = 'sv_SE',
        LanguageLocaleKey = 'en_US',
        EmailEncodingKey = 'UTF-8'
      );
    }
  }

  @isTest
  static void portalUserSeesOnlyOwnMoney() {
    User u = portalUser();
    System.runAs(u) {
      PMS_PortalMoneyController.payBaseOverride = 'https://example.test/pay';
      Test.startTest();
      PMS_PortalMoneyController.Result res = PMS_PortalMoneyController.getMyPayments();
      Test.stopTest();

      Assert.isTrue(res.hasAccount);
      Assert.areEqual(
        2,
        res.invoices.size(),
        'draft and other-account invoices are hidden'
      );
      PMS_PortalMoneyController.InvoiceRow first = res.invoices[0];
      Assert.areEqual(
        Date.today().addDays(-5),
        first.dueDate,
        'ordered by due date'
      );
      PMS_ExperienceTestFactory.num(9000, first.balance, 'overdue balance');
      Assert.isTrue(first.overdue);
      Assert.areEqual('Reminder 1', first.stage);
      Assert.areEqual(
        'https://example.test/pay/services/apexrest/pms/pay?i=' +
          first.id +
          '&k=key+with%2Fspace',
        first.payUrl
      );
      PMS_PortalMoneyController.InvoiceRow second = res.invoices[1];
      PMS_ExperienceTestFactory.num(100, second.balance, 'upcoming balance');
      Assert.isFalse(second.overdue);
      Assert.isNull(second.payUrl, 'no pay key, no link');
      // Invoice and instalments use the invoice's Currency_Code__c; rent changes use the site's.
      Assert.areEqual('SEK', first.currencyCode);
      Assert.areEqual('SEK', second.currencyCode);
      Assert.areEqual('SEK', res.instalments[0].currencyCode);
      Assert.areEqual('NOK', res.rentChanges[0].currencyCode);

      Assert.areEqual(2, res.instalments.size(), 'cancelled plan is hidden');
      Assert.isTrue(res.instalments[0].overdue);
      Assert.areEqual(1, res.instalments[0].instalmentNumber);
      Assert.isFalse(res.instalments[1].overdue);
      Assert.isNotNull(res.instalments[0].invoiceName);
      PMS_ExperienceTestFactory.num(
        4500,
        res.instalments[0].amount,
        'instalment'
      );

      Assert.areEqual(1, res.cardsNeeded.size(), 'cancelled booking is hidden');
      Assert.areEqual('Awaiting Card', res.cardsNeeded[0].status);
      Assert.areEqual('Test Hotel', res.cardsNeeded[0].siteName);

      Assert.areEqual(
        1,
        res.rentChanges.size(),
        'draft and year-old changes are hidden'
      );
      Assert.areEqual('Notice Sent', res.rentChanges[0].status);
      PMS_ExperienceTestFactory.num(
        9000,
        res.rentChanges[0].oldRent,
        'old rent'
      );
      PMS_ExperienceTestFactory.num(
        9270,
        res.rentChanges[0].newRent,
        'new rent'
      );
    }
  }

  @isTest
  static void payLinkComesFromSettingsAndIsOmittedWhenBlank() {
    System.runAs(admin()) {
      insert new PMS_Settings__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        Public_Pay_URL__c = 'https://sites.example.test/pay/'
      );
    }
    System.runAs(portalUser()) {
      Assert.areEqual(
        'https://sites.example.test/pay',
        PMS_PortalMoneyController.payBase()
      );
      PMS_PortalMoneyController.Result res = PMS_PortalMoneyController.getMyPayments();
      Assert.isTrue(
        res.invoices[0]
          .payUrl.startsWith(
            'https://sites.example.test/pay/services/apexrest/pms/pay?i='
          ),
        res.invoices[0].payUrl
      );
      PMS_PortalMoneyController.payBaseOverride = '';
      Assert.areEqual('', PMS_PortalMoneyController.payBase());
      PMS_PortalMoneyController.payBaseOverride = null;
    }
    System.runAs(admin()) {
      PMS_Settings__c s = PMS_Settings__c.getOrgDefaults();
      s.Public_Pay_URL__c = null;
      update s;
      Assert.isNull(
        PMS_PortalMoneyController.payBase(),
        'blank setting means no pay links'
      );
    }
  }

  @isTest
  static void internalUserWithoutContactGetsEmptyResult() {
    System.runAs(admin()) {
      PMS_PortalMoneyController.Result res = PMS_PortalMoneyController.getMyPayments();
      Assert.isFalse(res.hasAccount);
      Assert.isTrue(res.invoices.isEmpty());
      Assert.isTrue(res.instalments.isEmpty());
      Assert.isTrue(res.cardsNeeded.isEmpty());
      Assert.isTrue(res.rentChanges.isEmpty());
    }
  }

  @isTest
  static void accountOverrideIsHonouredInTests() {
    Account other = [SELECT Id FROM Account WHERE Name = 'Other Tenant AB'];
    PMS_PortalMoneyController.accountOverride = other.Id;
    PMS_PortalMoneyController.Result res = PMS_PortalMoneyController.getMyPayments();
    Assert.isTrue(res.hasAccount);
    Assert.areEqual(
      1,
      res.invoices.size(),
      'only the other account\'s invoice'
    );
    Assert.isTrue(res.instalments.isEmpty());
    Assert.isTrue(res.rentChanges.isEmpty());
  }

  @isTest
  static void currencyPrefersRecordCodeThenIsoThenOrgDefault() {
    PMS_Invoice__c withCode = new PMS_Invoice__c(Currency_Code__c = 'SEK');
    Assert.areEqual(
      'SEK',
      PMS_PortalMoneyController.iso(withCode, 'Currency_Code__c')
    );

    PMS_Invoice__c blank = new PMS_Invoice__c(Currency_Code__c = ' ');
    String expected = UserInfo.getDefaultCurrency();
    if (UserInfo.isMultiCurrencyOrganization()) {
      blank.put('CurrencyIsoCode', expected);
    }
    Assert.areEqual(
      expected,
      PMS_PortalMoneyController.iso(blank, 'Currency_Code__c')
    );

    PMS_Payment_Plan_Instalment__c inst = new PMS_Payment_Plan_Instalment__c(
      Plan__r = new PMS_Payment_Plan__c(
        Invoice__r = new PMS_Invoice__c(Currency_Code__c = 'DKK')
      )
    );
    Assert.areEqual(
      'DKK',
      PMS_PortalMoneyController.iso(inst, 'Plan__r.Invoice__r.Currency_Code__c')
    );
    Assert.areEqual(
      expected,
      PMS_PortalMoneyController.iso(
        new PMS_Payment_Plan_Instalment__c(),
        'Plan__r.Invoice__r.Currency_Code__c'
      ),
      'no parent loaded: falls back'
    );
  }

  @isTest
  static void invoiceListIsCappedAtFifty() {
    Id tenantId = portalUser().Contact.AccountId;
    System.runAs(admin()) {
      List<PMS_Invoice__c> invs = new List<PMS_Invoice__c>();
      for (Integer i = 0; i < 60; i++) {
        invs.add(
          new PMS_Invoice__c(
            Account__c = tenantId,
            Status__c = 'Issued',
            Issue_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Currency_Code__c = 'SEK'
          )
        );
      }
      insert invs;
      List<PMS_Charge__c> charges = new List<PMS_Charge__c>();
      for (PMS_Invoice__c inv : invs) {
        charges.add(
          new PMS_Charge__c(
            Invoice__c = inv.Id,
            Account__c = tenantId,
            Charge_Type__c = 'Other',
            Description__c = 'Bulk',
            Quantity__c = 1,
            Unit_Price__c = 10,
            Tax_Rate__c = 0,
            Status__c = 'Invoiced'
          )
        );
      }
      insert charges;
    }
    System.runAs(portalUser()) {
      Test.startTest();
      PMS_PortalMoneyController.Result res = PMS_PortalMoneyController.getMyPayments();
      Test.stopTest();
      Assert.areEqual(50, res.invoices.size());
    }
  }
}
