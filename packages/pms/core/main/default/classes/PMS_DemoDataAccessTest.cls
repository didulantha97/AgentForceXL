/**
 * A user holding PMS_App_Access only (no PMS_Manage_Demo_Data custom permission, no Modify All Data) can neither
 * load nor reset demo data, and the card hides. Lives in Core because PMS_DemoDataController is not namespace accessible.
 */
@IsTest
private class PMS_DemoDataAccessTest {
  @IsTest
  static void appAccessOnlyUserIsRefusedByTheDemoDataController() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String key = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
    User u = new User(
      Alias = 'dd' + key.left(5),
      Email = 'pms.demo.' + key + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Demo staff',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'pms.demo.' + key + '@example.com.test'
    );
    insert u;
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'PMS_App_Access'
    ];
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = ps.Id
    );

    System.runAs(u) {
      PMS_DemoData.Status st = PMS_DemoDataController.getStatus();
      Assert.isFalse(st.allowed, 'the card hides for staff');
      Assert.isTrue(st.packs.isEmpty(), 'nothing is revealed');
      Assert.isNotNull(st.reason);

      PMS_DemoData.Status loaded = PMS_DemoDataController.load('baseline');
      Assert.isTrue(loaded.message.startsWith('Refused'), loaded.message);
      Assert.isFalse(loaded.allowed);
      PMS_DemoData.Status gone = PMS_DemoDataController.reset('all');
      Assert.isTrue(gone.message.startsWith('Refused'), gone.message);
    }
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Demo_Record__c],
      'nothing was loaded or removed'
    );
  }
}
