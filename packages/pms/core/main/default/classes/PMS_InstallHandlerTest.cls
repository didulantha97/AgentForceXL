@isTest
private class PMS_InstallHandlerTest {
  private static User makeUser(Boolean active) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String key = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
    User u = new User(
      Alias = 'inst' + key.left(4),
      Email = 'pms.install.' + key + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Installer',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'pms.install.' + key + '@example.com.test',
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

  private static final List<String> ALL = new List<String>{
    'PMS_Core_Admin',
    'PMS_App_Access',
    'PMS_Access_Manager',
    'PMS_Channex',
    'PMS_Dynamic_Pricing',
    'PMS_Rent_Review',
    'PMS_Guest360_Viewer',
    'PMS_Guest360_Editor'
  };

  @isTest
  static void freshInstallAssignsEveryCoreAdminSetAndIsIdempotent() {
    User u = makeUser(true);
    Assert.areEqual(
      ALL.size(),
      PMS_InstallHandler.assignToInstaller(
        u.Id,
        PMS_InstallHandler.setsFor(null)
      )
    );
    Assert.isTrue(assigned(u.Id).containsAll(new Set<String>(ALL)));
    Assert.areEqual(
      0,
      PMS_InstallHandler.assignToInstaller(u.Id, ALL),
      'Second run adds nothing'
    );
  }

  @isTest
  static void fillsOnlyTheMissingSet() {
    User u = makeUser(true);
    String ns = PMS_InstallHandler.packageNamespace();
    PermissionSet app = [
      SELECT Id
      FROM PermissionSet
      WHERE
        Name = 'PMS_App_Access'
        AND NamespacePrefix = :(String.isBlank(ns) ? null : ns)
    ];
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = app.Id
    );
    Assert.areEqual(
      ALL.size() - 1,
      PMS_InstallHandler.assignToInstaller(u.Id, ALL)
    );
  }

  @isTest
  static void freshInstallRunsThroughTheHandler() {
    User u = makeUser(true);
    System.runAs(u) {
      Test.testInstall(new PMS_InstallHandler(), null);
    }
    Assert.isTrue(
      assigned(u.Id).containsAll(new Set<String>(ALL)),
      'Fresh install'
    );
  }

  @isTest
  static void upgradeAssignsNothingWhenNoSetIsNew() {
    User u = makeUser(true);
    System.runAs(u) {
      Test.testInstall(new PMS_InstallHandler(), new Version(1, 0));
    }
    Assert.isFalse(
      assigned(u.Id).contains('PMS_Core_Admin'),
      'Existing sets are not re-added on upgrade'
    );
    Assert.isTrue(PMS_InstallHandler.setsFor(new Version(1, 0, 0)).isEmpty());
  }

  @isTest
  static void upgradeAssignsOnlySetsAddedAfterThePreviousVersion() {
    PMS_InstallHandler.addedIn = new Map<String, String>{
      'PMS_Rent_Review' => '1.1',
      'PMS_Channex' => '1.0.5',
      'PMS_Core_Admin' => '1.2.0'
    };
    Assert.areEqual(
      new Set<String>{ 'PMS_Rent_Review', 'PMS_Channex', 'PMS_Core_Admin' },
      new Set<String>(PMS_InstallHandler.setsFor(new Version(1, 0, 0)))
    );
    Assert.areEqual(
      new Set<String>{ 'PMS_Rent_Review', 'PMS_Core_Admin' },
      new Set<String>(PMS_InstallHandler.setsFor(new Version(1, 0, 5)))
    );
    Assert.areEqual(
      new Set<String>{ 'PMS_Core_Admin' },
      new Set<String>(PMS_InstallHandler.setsFor(new Version(1, 1, 0)))
    );
    Assert.isTrue(PMS_InstallHandler.setsFor(new Version(1, 2, 0)).isEmpty());
    Assert.areEqual(ALL.size(), PMS_InstallHandler.setsFor(null).size());

    User u = makeUser(true);
    System.runAs(u) {
      Test.testInstall(new PMS_InstallHandler(), new Version(1, 0, 0));
    }
    Set<String> have = assigned(u.Id);
    Assert.isTrue(have.contains('PMS_Rent_Review'));
    Assert.isTrue(have.contains('PMS_Channex'));
    Assert.isFalse(have.contains('PMS_App_Access'), 'Not new, not assigned');
  }

  @isTest
  static void pushUpgradeAssignsNothing() {
    User u = makeUser(true);
    PMS_InstallHandler.addedIn = new Map<String, String>{
      'PMS_Rent_Review' => '1.1'
    };
    System.runAs(u) {
      Test.testInstall(new PMS_InstallHandler(), new Version(1, 0), true);
    }
    Assert.isFalse(assigned(u.Id).contains('PMS_Rent_Review'));
  }

  @isTest
  static void skipsInactiveUserAndNullId() {
    User u = makeUser(false);
    Assert.areEqual(0, PMS_InstallHandler.assignToInstaller(u.Id, ALL));
    Assert.areEqual(0, PMS_InstallHandler.assignToInstaller(null, ALL));
  }

  @isTest
  static void failureNeverFailsTheInstall() {
    PMS_InstallHandler.failAccessForTest = true;
    Test.testInstall(new PMS_InstallHandler(), null);
    Assert.isTrue(true, 'No exception escaped');
  }

  @isTest
  static void namespaceIsDerivedFromTheClass() {
    String ns = PMS_InstallHandler.packageNamespace();
    Assert.isNotNull(ns);
    Assert.areEqual(
      ns == '' ? 'PMS_InstallHandler' : ns + '.PMS_InstallHandler',
      PMS_InstallHandler.class.getName()
    );
  }
}
