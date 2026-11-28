/**
 * Experience half of the access smoke test per persona (Core controllers are covered by PMS_AccessPersonaCoreTest in Core). Creates an Admin user (PMS_Core_Admin + PMS_App_Access + the add-on and
 * Experience admin sets) and a Staff user (PMS_Standard_User permission set group) on the Standard User
 * profile, then runs the Experience panels and CRUD/FLS checks as each user.
 * Mirrors packages/pms/scripts/access-audit.js (which checks the same rules from source).
 *
 * Limit of this test: Apex class access (setupEntityAccess) is not enforced for Apex-to-Apex calls, so a
 * missing classAccess on a controller does NOT fail here; the audit script covers that. Object CRUD and
 * field-level security ARE enforced (USER_MODE queries and DML).
 */
@isTest
private class PMS_AccessPersonaTest {
  private static final List<String> ADMIN_SETS = new List<String>{
    'PMS_Core_Admin',
    'PMS_App_Access',
    'PMS_Access_Manager',
    'PMS_Channex',
    'PMS_Dynamic_Pricing',
    'PMS_Rent_Review',
    'PMS_Guest360_Viewer',
    'PMS_Guest360_Editor',
    'PMS_Experience_Access',
    'PMS_Payment_Integration',
    'PMS_Payment_Gateway',
    'PMS_Stripe_Access',
    'PMS_Dunning',
    'PMS_Guarantees',
    'PMS_Customer_Portal_Management',
    'PMS_Partner_Management'
  };

  private static User makeUser(String tag) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
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
    return u;
  }

  private static User adminUser() {
    User u = makeUser('adm');
    List<PermissionSetAssignment> add = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN :ADMIN_SETS
    ]) {
      add.add(
        new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id)
      );
    }
    insert add;
    return u;
  }

  private static User staffUser() {
    User u = makeUser('stf');
    PermissionSetGroup g = [
      SELECT Id
      FROM PermissionSetGroup
      WHERE DeveloperName = 'PMS_Standard_User'
    ];
    Test.calculatePermissionSetGroup(g.Id);
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetGroupId = g.Id
    );
    return u;
  }

  private static User persona(String who) {
    return who == 'Admin' ? adminUser() : staffUser();
  }

  /** The Experience panels on the _Plus record pages: Card and Deposit (booking) and Dunning (invoice). */
  private static void panelsFor(String who) {
    User u = persona(who);
    System.runAs(u) {
      PMS_ExperienceTestFactory.Hotel h = PMS_ExperienceTestFactory.hotel(2);
      PMS_Booking__c b = PMS_BookingService.createBooking(
        PMS_ExperienceTestFactory.hotelRequest(h, Date.today().addDays(3), 2)
      );
      Assert.isNotNull(
        PMS_GuaranteeController.getState(b.Id),
        who + ' guarantee panel'
      );
      PMS_Invoice__c inv = new PMS_Invoice__c(
        Account__c = h.guestAccount.Id,
        Booking__c = b.Id,
        Issue_Date__c = Date.today().addDays(-20),
        Due_Date__c = Date.today().addDays(-5),
        Currency_Code__c = 'SEK',
        Status__c = 'Issued',
        Subtotal__c = 1000,
        Tax_Total__c = 0,
        Amount_Paid__c = 0
      );
      insert inv;
      Assert.isNotNull(
        PMS_DunningController.getState(inv.Id),
        who + ' dunning panel'
      );
    }
  }

  /** CRUD / FLS smoke with USER_MODE DML, which enforces object CRUD and field-level security. */
  private static void crudSmoke(String who, Boolean canDelete) {
    Account a = new Account(Name = who + ' smoke');
    insert as user a;
    PMS_Site__c site = new PMS_Site__c(
      Name = who + ' Hotel',
      RecordTypeId = PMS_ExperienceTestFactory.rt(
        PMS_Site__c.SObjectType,
        'Hotel'
      ),
      Module__c = 'Hotel',
      Status__c = 'Active',
      Time_Zone__c = 'Europe/Stockholm',
      Currency_Code__c = 'SEK'
    );
    insert as user site;
    PMS_Space_Type__c st = new PMS_Space_Type__c(
      Name = 'Double',
      Site__c = site.Id,
      Default_Rate__c = 1000,
      Default_Occupancy__c = 2
    );
    insert as user st;
    PMS_Space__c sp = new PMS_Space__c(
      Name = '101',
      RecordTypeId = PMS_ExperienceTestFactory.rt(
        PMS_Space__c.SObjectType,
        'Room'
      ),
      Site__c = site.Id,
      Space_Type__c = st.Id,
      Max_Occupancy__c = 2,
      Bookable__c = true
    );
    insert as user sp;
    List<PMS_Site__c> back = [
      SELECT Id, Name, Module__c, Status__c, Time_Zone__c, Currency_Code__c
      FROM PMS_Site__c
      WHERE Id = :site.Id
      WITH USER_MODE
    ];
    Assert.areEqual(1, back.size(), who + ' reads back its site');
    site.Status__c = 'Inactive';
    update as user site;
    if (canDelete) {
      delete as user sp;
    } else {
      try {
        delete as user sp;
        Assert.fail(
          who + ' must not delete spaces (muted by the Standard User group)'
        );
      } catch (System.TypeException e) {
        Assert.isTrue(e.getMessage().contains('not allowed'), e.getMessage());
      }
    }
  }

  @isTest
  static void adminExperiencePanels() {
    panelsFor('Admin');
  }

  @isTest
  static void adminCrudSmoke() {
    System.runAs(persona('Admin')) {
      crudSmoke('Admin', true);
    }
  }

  @isTest
  static void staffExperiencePanels() {
    panelsFor('Staff');
  }

  @isTest
  static void staffCrudSmoke() {
    System.runAs(persona('Staff')) {
      crudSmoke('Staff', false);
    }
  }

  @isTest
  static void adminHoldsEveryFeaturePermission() {
    System.runAs(adminUser()) {
      Assert.isTrue(
        Schema.sObjectType.PMS_Demo_Record__c.isCreateable(),
        'Admin may use demo data'
      );
      Assert.isTrue(
        Schema.sObjectType.PMS_Invoice__c.isDeletable(),
        'Admin may delete invoices'
      );
      Assert.isTrue(
        Schema.sObjectType.PMS_Payment_Policy__c.isCreateable(),
        'Admin edits policies'
      );
      Assert.isTrue(FeatureManagement.checkPermission('PMS_Manage_License'));
      Assert.isTrue(FeatureManagement.checkPermission('PMS_Manage_Demo_Data'));
      Assert.isTrue(FeatureManagement.checkPermission('PMS_Manage_Access'));
      Assert.isFalse(
        FeatureManagement.checkPermission('PMS_Hide_Amounts'),
        'Negative switches are never assigned by hand'
      );
    }
  }

  @isTest
  static void staffKeepsTheMutedRestrictions() {
    User u = staffUser();
    System.runAs(u) {
      Assert.isFalse(
        Schema.sObjectType.PMS_Invoice__c.isDeletable(),
        'No delete on invoices'
      );
      Assert.isFalse(
        Schema.sObjectType.PMS_Payment__c.isDeletable(),
        'No delete on payments'
      );
      Assert.isFalse(
        Schema.sObjectType.PMS_Booking__c.isDeletable(),
        'No delete on bookings'
      );
      Assert.isTrue(
        Schema.sObjectType.PMS_Payment_Policy__c.isAccessible(),
        'Policies readable'
      );
      Assert.isFalse(
        Schema.sObjectType.PMS_Payment_Policy__c.isCreateable(),
        'Policies read-only'
      );
      Assert.isFalse(
        Schema.sObjectType.PMS_Dunning_Policy__c.isUpdateable(),
        'Policies read-only'
      );
      Assert.isFalse(
        Schema.sObjectType.PMS_Access_Rule__c.isUpdateable(),
        'Access rules read-only'
      );
      Assert.isFalse(
        Schema.sObjectType.PMS_Channel_Mapping__c.isCreateable(),
        'Config read-only'
      );
      Assert.isFalse(
        Schema.sObjectType.PMS_Demo_Record__c.isAccessible(),
        'Demo bookkeeping is admin-only'
      );
      Assert.isFalse(FeatureManagement.checkPermission('PMS_Manage_License'));
      Assert.isFalse(FeatureManagement.checkPermission('PMS_Manage_Demo_Data'));
      Assert.isFalse(FeatureManagement.checkPermission('PMS_Manage_Access'));
      Assert.isFalse(
        Schema.sObjectType.PMS_Invoice__c.fields.Pay_Key__c.isAccessible(),
        'The pay-link key is never visible'
      );
    }
  }
}
