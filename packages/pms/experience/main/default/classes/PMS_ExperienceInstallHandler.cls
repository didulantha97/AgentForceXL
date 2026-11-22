/**
 * Post-install script for PMS Experience. Gives the installing admin the Experience permission sets
 * an administrator needs: all of them on a fresh install, only sets listed in addedIn on an upgrade,
 * skipping any already assigned. PMS Core's own
 * handler assigns the Core sets. Nothing here may fail the install: errors are only logged.
 *
 * PMS_Payment_Integration and PMS_Payment_Gateway (payment webhooks) are integration only: never assigned to the
 * installer, never in the Standard User group.
 *
 * Not assigned on purpose: PMS_Payment_Link, PMS_Public_Booking, PMS_Guest_Check_In (site guest users),
 * PMS_Customer_Portal, PMS_Partner_Portal (portal user profiles).
 */
global with sharing class PMS_ExperienceInstallHandler implements InstallHandler {
  @TestVisible
  private static Boolean failForTest = false;

  private static final List<String> INSTALLER_PERMSETS = new List<String>{
    'PMS_Experience_Access',
    'PMS_Stripe_Access',
    'PMS_Dunning',
    'PMS_Guarantees',
    'PMS_Customer_Portal_Management',
    'PMS_Partner_Management'
  };

  /**
   * Permission set name => package version it first shipped in ('1.1' or '1.1.0'). On an upgrade only sets listed here
   * whose version is newer than the previous version are assigned; a fresh install assigns every set. Add a line
   * whenever a release adds an admin permission set. Initially empty.
   */
  @TestVisible
  private static Map<String, String> addedIn = new Map<String, String>();

  global void onInstall(InstallContext context) {
    try {
      if (failForTest) {
        throw new IllegalArgumentException('forced');
      }
      // Push upgrades have no human installer; assigning admin rights to that user would be wrong.
      if (context != null && !context.isPush()) {
        assignToInstaller(
          context.installerId(),
          setsFor(context.previousVersion())
        );
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS Experience permission sets not assigned to the installer: ' +
        e.getMessage()
      );
    }
  }

  /** Sets to assign: all on a fresh install; on an upgrade only those added after the previous version. */
  @TestVisible
  private static List<String> setsFor(Version previous) {
    if (previous == null) {
      return INSTALLER_PERMSETS;
    }
    List<String> names = new List<String>();
    for (String name : INSTALLER_PERMSETS) {
      String v = addedIn.get(name);
      if (v == null) {
        continue;
      }
      List<String> parts = v.split('\\.');
      Version added = new Version(
        Integer.valueOf(parts[0]),
        parts.size() > 1 ? Integer.valueOf(parts[1]) : 0,
        parts.size() > 2 ? Integer.valueOf(parts[2]) : 0
      );
      if (previous.compareTo(added) < 0) {
        names.add(name);
      }
    }
    return names;
  }

  /** Namespace of this package ('' when unmanaged), taken from this class so no prefix is hard-coded. */
  @TestVisible
  private static String packageNamespace() {
    List<String> parts = PMS_ExperienceInstallHandler.class
      .getName()
      .split('\\.');
    return parts.size() > 1 ? parts[0] : '';
  }

  /** Assigns the Experience admin permission sets to the user. Returns the number added. */
  @TestVisible
  private static Integer assignToInstaller(Id userId, List<String> setNames) {
    if (userId == null || setNames.isEmpty()) {
      return 0;
    }
    // Setup objects (PermissionSet, PermissionSetAssignment) are managed by the package in system context.
    List<User> users = [
      SELECT Id
      FROM User
      WHERE Id = :userId AND IsActive = TRUE AND UserType = 'Standard'
      LIMIT 1
    ];
    if (users.isEmpty()) {
      return 0;
    }
    String ns = packageNamespace();
    Map<Id, PermissionSet> sets = new Map<Id, PermissionSet>(
      [
        SELECT Id, Name
        FROM PermissionSet
        WHERE
          Name IN :setNames
          AND NamespacePrefix = :(String.isBlank(ns) ? null : ns)
      ]
    );
    Set<Id> have = new Set<Id>();
    for (PermissionSetAssignment a : [
      SELECT PermissionSetId
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId AND PermissionSetId IN :sets.keySet()
    ]) {
      have.add(a.PermissionSetId);
    }
    List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
    for (Id psId : sets.keySet()) {
      if (!have.contains(psId)) {
        toAdd.add(
          new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = psId
          )
        );
      }
    }
    Integer added = 0;
    for (Database.SaveResult r : Database.insert(toAdd, false)) {
      if (r.isSuccess()) {
        added++;
      } else {
        System.debug(
          LoggingLevel.ERROR,
          'PMS permission set not assigned: ' + r.getErrors()[0].getMessage()
        );
      }
    }
    return added;
  }
}
