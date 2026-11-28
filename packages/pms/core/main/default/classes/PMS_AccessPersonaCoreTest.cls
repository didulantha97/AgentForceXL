/**
 * Core half of the access smoke test: runs every Core home controller and the main UI calls as an Admin
 * (Core permission sets) and a Staff user (PMS_App_Access + PMS_Core_Admin). Home controllers catch their own
 * errors into "warnings", so a missing object or field permission fails here. The Experience half (panels,
 * Standard User group restrictions) is PMS_AccessPersonaTest in the Experience package.
 */
@isTest
private class PMS_AccessPersonaCoreTest {
  private static final List<String> ADMIN_SETS = new List<String>{
    'PMS_Core_Admin',
    'PMS_App_Access',
    'PMS_Access_Manager',
    'PMS_Channex',
    'PMS_Dynamic_Pricing',
    'PMS_Rent_Review',
    'PMS_Guest360_Viewer',
    'PMS_Guest360_Editor'
  };
  private static final List<String> STAFF_SETS = new List<String>{
    'PMS_Core_Admin',
    'PMS_App_Access'
  };

  private static User persona(String who) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String tag = who.left(3).toLowerCase();
    String key = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
    User u = new User(
      Alias = tag + key.left(3),
      Email = 'pms.' + tag + '.' + key + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Persona ' + tag,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'pms.' + tag + '.' + key + '@example.com.test'
    );
    insert u;
    List<PermissionSetAssignment> add = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN :(who == 'Admin' ? ADMIN_SETS : STAFF_SETS)
    ]) {
      add.add(
        new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id)
      );
    }
    insert add;
    return u;
  }

  private static void homeFor(String who, String module) {
    System.runAs(persona(who)) {
      PMS_HomeController.HomeData d = PMS_HomeController.getHome(module, null);
      Assert.isNotNull(d, who + ' ' + module + ' home');
      Assert.isTrue(
        d.warnings.isEmpty(),
        who + ' ' + module + ' home warnings: ' + d.warnings
      );
      PMS_RevenueHomeController.Result r = PMS_RevenueHomeController.getAttention(
        module
      );
      Assert.isTrue(
        r.warnings.isEmpty(),
        who + ' ' + module + ' attention warnings: ' + r.warnings
      );
      PMS_RevenueHomeController.reportIds();
    }
  }

  private static void uiFor(String who) {
    System.runAs(persona(who)) {
      PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(2);
      PMS_TestDataFactory.Property prop = PMS_TestDataFactory.property();
      PMS_TestDataFactory.Practice prac = PMS_TestDataFactory.practice();
      PMS_Project__c proj = PMS_TestDataFactory.projectWithTasks();
      Assert.isFalse(
        PMS_UIController.getEnabledModules().isEmpty(),
        who + ' modules'
      );
      PMS_UIController.getSites('Hotel');
      PMS_UIController.getSpaceTypes(h.site.Id);
      PMS_UIController.getRatePlans(h.site.Id, 'Hotel');
      PMS_UIController.getServices();
      PMS_UIController.getRoomGrid(h.site.Id, Date.today(), 7);
      PMS_UIController.getFrontDesk(h.site.Id, Date.today());
      PMS_UIController.getRentRoll(prop.site.Id);
      PMS_UIController.getGantt(proj.Id);
      PMS_UIController.getPractitionerWeek(
        prac.site.Id,
        Date.today().toStartOfWeek()
      );
      Assert.isNotNull(
        PMS_LicenceController.getStatus(),
        who + ' licence status'
      );
    }
  }

  @isTest
  static void adminHomeAdmin() {
    homeFor('Admin', 'Admin');
  }
  @isTest
  static void adminHomeHotel() {
    homeFor('Admin', 'Hotel');
  }
  @isTest
  static void adminHomeProperty() {
    homeFor('Admin', 'Property');
  }
  @isTest
  static void adminHomeProjects() {
    homeFor('Admin', 'Projects');
  }
  @isTest
  static void adminHomePractice() {
    homeFor('Admin', 'Practice');
  }
  @isTest
  static void adminUiControllers() {
    uiFor('Admin');
  }
  @isTest
  static void staffHomeAdmin() {
    homeFor('Staff', 'Admin');
  }
  @isTest
  static void staffHomeHotel() {
    homeFor('Staff', 'Hotel');
  }
  @isTest
  static void staffHomeProperty() {
    homeFor('Staff', 'Property');
  }
  @isTest
  static void staffHomeProjects() {
    homeFor('Staff', 'Projects');
  }
  @isTest
  static void staffHomePractice() {
    homeFor('Staff', 'Practice');
  }
  @isTest
  static void staffUiControllers() {
    uiFor('Staff');
  }
}
