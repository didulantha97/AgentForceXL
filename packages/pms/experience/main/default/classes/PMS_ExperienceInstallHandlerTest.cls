@isTest
private class PMS_ExperienceInstallHandlerTest {
  private static final Set<String> EXPECTED = new Set<String>{
    'PMS_Experience_Access',
    'PMS_Stripe_Access',
    'PMS_Dunning',
    'PMS_Guarantees',
    'PMS_Customer_Portal_Management',
    'PMS_Partner_Management'
  };

  private static User makeUser(Boolean active) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String key = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
    User u = new User(
      Alias = 'xins' + key.left(4),
      Email = 'pms.xinstall.' + key + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Installer',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'pms.xinstall.' + key + '@example.com.test',
      IsActive = active
    );
    insert u;
    return u;
  }

  private static Set<String> assigned(Id userId) {
    Set<String> names = new Set<String>();
    for (PermissionSetAssignment a : [
      SELECT PermissionSet.Name
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId
    ]) {
      names.add(a.PermissionSet.Name);
    }
    return names;
  }

  @isTest
  static void assignsAdminSetsAndIsIdempotent() {
    User u = makeUser(true);
    Assert.areEqual(
      EXPECTED.size(),
      PMS_ExperienceInstallHandler.assignToInstaller(
        u.Id,
        PMS_ExperienceInstallHandler.setsFor(null)
      )
    );
    Set<String> names = assigned(u.Id);
    Assert.isTrue(names.containsAll(EXPECTED));
    Assert.isFalse(
      names.contains('PMS_Payment_Link'),
      'Guest-only sets are never assigned'
    );
    Assert.isFalse(
      names.contains('PMS_Payment_Integration'),
      'Integration-only sets are never assigned to the installer'
    );
    Assert.isFalse(names.contains('PMS_Payment_Gateway'));
    Assert.isFalse(names.contains('PMS_Public_Booking'));
    Assert.areEqual(
      0,
      PMS_ExperienceInstallHandler.assignToInstaller(
        u.Id,
        PMS_ExperienceInstallHandler.setsFor(null)
      )
    );
  }

  @isTest
  static void freshInstallRunsThroughTheHandler() {
    User u = makeUser(true);
    System.runAs(u) {
      Test.testInstall(new PMS_ExperienceInstallHandler(), null);
    }
    Assert.isTrue(assigned(u.Id).containsAll(EXPECTED), 'Fresh install');
  }

  @isTest
  static void upgradeAssignsOnlySetsAddedAfterThePreviousVersion() {
    User u = makeUser(true);
    System.runAs(u) {
      Test.testInstall(
        new PMS_ExperienceInstallHandler(),
        new Version(1, 0, 0)
      );
    }
    Assert.isFalse(
      assigned(u.Id).contains('PMS_Dunning'),
      'Nothing new, nothing assigned'
    );
    PMS_ExperienceInstallHandler.addedIn = new Map<String, String>{
      'PMS_Dunning' => '1.1'
    };
    Assert.areEqual(
      new List<String>{ 'PMS_Dunning' },
      PMS_ExperienceInstallHandler.setsFor(new Version(1, 0, 0))
    );
    Assert.isTrue(
      PMS_ExperienceInstallHandler.setsFor(new Version(1, 1, 0)).isEmpty()
    );
    System.runAs(u) {
      Test.testInstall(
        new PMS_ExperienceInstallHandler(),
        new Version(1, 0, 0)
      );
    }
    Assert.isTrue(assigned(u.Id).contains('PMS_Dunning'));
    Assert.isFalse(assigned(u.Id).contains('PMS_Stripe_Access'));
  }

  @isTest
  static void pushUpgradeAssignsNothing() {
    User u = makeUser(true);
    PMS_ExperienceInstallHandler.addedIn = new Map<String, String>{
      'PMS_Dunning' => '1.1'
    };
    System.runAs(u) {
      Test.testInstall(
        new PMS_ExperienceInstallHandler(),
        new Version(1, 0, 0),
        true
      );
    }
    Assert.isFalse(assigned(u.Id).contains('PMS_Dunning'));
  }

  @isTest
  static void skipsInactiveUserAndNullId() {
    User u = makeUser(false);
    Assert.areEqual(
      0,
      PMS_ExperienceInstallHandler.assignToInstaller(
        u.Id,
        PMS_ExperienceInstallHandler.setsFor(null)
      )
    );
    Assert.areEqual(
      0,
      PMS_ExperienceInstallHandler.assignToInstaller(
        null,
        PMS_ExperienceInstallHandler.setsFor(null)
      )
    );
  }

  @isTest
  static void failureNeverFailsTheInstall() {
    PMS_ExperienceInstallHandler.failForTest = true;
    Test.testInstall(new PMS_ExperienceInstallHandler(), null);
    Assert.isTrue(true, 'No exception escaped');
  }

  @isTest
  static void namespaceIsDerivedFromTheClass() {
    String ns = PMS_ExperienceInstallHandler.packageNamespace();
    Assert.areEqual(
      ns == ''
        ? 'PMS_ExperienceInstallHandler'
        : ns + '.PMS_ExperienceInstallHandler',
      PMS_ExperienceInstallHandler.class.getName()
    );
  }
}
