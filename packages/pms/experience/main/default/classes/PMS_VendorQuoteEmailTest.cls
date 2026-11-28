@isTest
private class PMS_VendorQuoteEmailTest {
  private static final Integer VENDOR_COUNT = 6;
  private static final Integer QUOTE_COUNT = 30;

  @isTest
  static void manyVendorsAndQuotesAcceptedInOneDmlUseCachedRecipientsAndOneSendEmail() {
    UserRole role = new UserRole(
      Name = 'PMS Vendor Mail Role',
      DeveloperName = 'PMS_Vendor_Mail_Role'
    );
    insert role;
    Profile sysAdmin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    Profile partner = [
      SELECT Id
      FROM Profile
      WHERE Name = :PMS_PortalUserSetup.PARTNER_PROFILE
      LIMIT 1
    ];
    String stamp = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User adm = new User(
      ProfileId = sysAdmin.Id,
      UserRoleId = role.Id,
      LastName = 'VendorMailAdmin',
      Alias = 'vmadm',
      Email = 'vm.admin@example.com',
      Username = 'vm.admin' + stamp + '@example.com',
      TimeZoneSidKey = 'Europe/Stockholm',
      LocaleSidKey = 'en_US',
      LanguageLocaleKey = 'en_US',
      EmailEncodingKey = 'UTF-8'
    );
    insert adm;

    List<PMS_Vendor_Quote__c> quotes = new List<PMS_Vendor_Quote__c>();
    System.runAs(adm) {
      PMS_ExperienceTestFactory.Property p = PMS_ExperienceTestFactory.property();
      List<Account> vendors = new List<Account>();
      for (Integer i = 0; i < VENDOR_COUNT; i++) {
        vendors.add(new Account(Name = 'Vendor ' + i, OwnerId = adm.Id));
      }
      insert vendors;
      List<Contact> contacts = new List<Contact>();
      for (Account a : vendors) {
        contacts.add(
          new Contact(
            AccountId = a.Id,
            LastName = 'Contact ' + a.Name,
            Email = 'c@example.com'
          )
        );
      }
      insert contacts;
      List<User> portalUsers = new List<User>();
      for (Integer i = 0; i < VENDOR_COUNT; i++) {
        portalUsers.add(
          new User(
            ProfileId = partner.Id,
            ContactId = contacts[i].Id,
            LastName = 'Vendor' + i,
            Alias = 'vend' + i,
            Email = 'vendor' + i + '.' + stamp + '@example.com',
            Username = 'vendor' + i + '.' + stamp + '@example.com',
            TimeZoneSidKey = 'Europe/Stockholm',
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8'
          )
        );
      }
      insert portalUsers;

      List<PMS_Work_Order__c> wos = new List<PMS_Work_Order__c>();
      for (Integer i = 0; i < QUOTE_COUNT; i++) {
        wos.add(
          new PMS_Work_Order__c(
            Site__c = p.site.Id,
            Space__c = p.unit.Id,
            Subject__c = 'Job ' + i,
            Priority__c = 'Medium',
            Status__c = 'New'
          )
        );
      }
      insert wos;
      for (Integer i = 0; i < QUOTE_COUNT; i++) {
        quotes.add(
          new PMS_Vendor_Quote__c(
            Work_Order__c = wos[i].Id,
            Vendor_Account__c = vendors[Math.mod(i, VENDOR_COUNT)].Id,
            Amount__c = 100,
            Tax_Amount__c = 25,
            Status__c = 'Submitted'
          )
        );
      }
      insert quotes;
      for (PMS_Vendor_Quote__c q : quotes) {
        q.Status__c = 'Accepted';
      }

      Test.startTest();
      Integer queriesBefore = Limits.getQueries();
      Integer emailsBefore = Limits.getEmailInvocations();
      update quotes;
      Integer queries = Limits.getQueries() - queriesBefore;
      Integer sendCalls = Limits.getEmailInvocations() - emailsBefore;
      Test.stopTest();

      Assert.areEqual(
        1,
        sendCalls,
        'one Messaging.sendEmail for all ' + QUOTE_COUNT + ' quotes'
      );
      // Constant overhead only: recipients (1 query for all vendors), message lookups, portal URL, sender. A per-quote or
      // per-vendor query would add at least 30 and exceed this bound.
      Assert.isTrue(
        queries < QUOTE_COUNT,
        'SOQL must not scale with quotes or vendors, used ' + queries
      );
      Assert.areEqual(
        QUOTE_COUNT,
        [SELECT COUNT() FROM PMS_Work_Order__c WHERE Status__c = 'Approved']
      );
    }
  }
}
