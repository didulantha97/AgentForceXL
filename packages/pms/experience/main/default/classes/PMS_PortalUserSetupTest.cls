@isTest
private class PMS_PortalUserSetupTest {
  private static User newUser(Id profileId, String alias) {
    String unique =
      alias +
      Datetime.now().getTime() +
      Crypto.getRandomInteger();
    return new User(
      ProfileId = profileId,
      Username = unique.replace('-', '') + '@pms-test.example',
      Email = alias + '@pms-test.example',
      LastName = alias,
      Alias = alias.left(8),
      TimeZoneSidKey = 'Europe/Stockholm',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }

  @isTest
  static void newPortalUserGetsStripeAccess() {
    Profile admin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    List<Profile> portalProfiles = [
      SELECT Id
      FROM Profile
      WHERE Name = :PMS_PortalUserSetup.PORTAL_PROFILE
      LIMIT 1
    ];
    // The PMS portal profiles come from packages/pms/org-setup, which is deployed after the managed
    // packages are installed. Package build orgs don't have them, so there's nothing to assert there.
    if (portalProfiles.isEmpty()) {
      return;
    }
    Profile portal = portalProfiles[0];
    UserRole role = new UserRole(Name = 'PMS Portal Test Role');
    insert role;
    User owner = newUser(admin.Id, 'pmsowner');
    owner.UserRoleId = role.Id;
    insert owner;

    User portalUser = newUser(portal.Id, 'pmsguest');
    System.runAs(owner) {
      Account a = new Account(Name = 'Portal Test Co', OwnerId = owner.Id);
      insert a;
      Contact c = new Contact(
        AccountId = a.Id,
        LastName = 'Portal',
        Email = 'pmsguest@pms-test.example'
      );
      insert c;
      portalUser.ContactId = c.Id;
      Test.startTest();
      insert portalUser;
      Test.stopTest();
    }
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :portalUser.Id
          AND PermissionSet.Name = :PMS_PortalUserSetup.STRIPE_PERMSET
      ]
    );

    // Running again does not add a second assignment.
    System.runAs(owner) {
      PMS_PortalUserSetup.assign(new Set<Id>{ portalUser.Id });
    }
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :portalUser.Id
          AND PermissionSet.Name = :PMS_PortalUserSetup.STRIPE_PERMSET
      ]
    );
  }

  @isTest
  static void internalUsersAreIgnored() {
    Profile admin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    User u = newUser(admin.Id, 'pmsstaff');
    Test.startTest();
    insert u;
    Test.stopTest();
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :u.Id
          AND PermissionSet.Name = :PMS_PortalUserSetup.STRIPE_PERMSET
      ]
    );
  }
}
