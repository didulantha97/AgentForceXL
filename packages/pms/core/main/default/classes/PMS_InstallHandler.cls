/**
 * Post-install script for PMS Core.
 *  1. Records the install date once; it starts the pilot period. Upgrades never restart it: the date
 *     is only written when blank (first install, or an org that upgraded from a version that
 *     pre-dates licensing).
 *  2. Gives the installing admin every Core admin permission set on a fresh install, so the person who
 *     installs the package can open every app and feature without a manual Setup step. On an upgrade only
 *     sets listed in addedIn for a newer version are assigned. Push upgrades assign nothing.
 * Nothing here may fail the install: every step is isolated and only logs.
 */
global with sharing class PMS_InstallHandler implements InstallHandler {
  @TestVisible
  private static Boolean failForTest = false;
  @TestVisible
  private static Boolean failAccessForTest = false;

  private static final List<String> INSTALLER_PERMSETS = new List<String>{
    'PMS_Core_Admin',
    'PMS_App_Access',
    'PMS_Access_Manager',
    'PMS_Channex',
    'PMS_Dynamic_Pricing',
    'PMS_Rent_Review'
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
      PMS_Entitlements.ensureInstallDate();
    } catch (Exception e) {
      // Never fail an install over licensing; the daily job records the date later.
      System.debug(
        LoggingLevel.ERROR,
        'PMS install date not recorded: ' + e.getMessage()
      );
    }
    try {
      if (failAccessForTest) {
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
        'PMS permission sets not assigned to the installer: ' + e.getMessage()
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
    List<String> parts = PMS_InstallHandler.class.getName().split('\\.');
    return parts.size() > 1 ? parts[0] : '';
  }

  /** Assigns the installer permission sets to the user, skipping any already assigned. Returns the number added. */
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
