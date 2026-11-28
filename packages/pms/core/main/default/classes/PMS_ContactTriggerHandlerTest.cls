@isTest
private class PMS_ContactTriggerHandlerTest {
  private static List<Contact> flagged(Integer n) {
    Account a = new Account(Name = 'Dup Acc');
    insert a;
    Contact original = new Contact(AccountId = a.Id, LastName = 'Original');
    Contact other = new Contact(AccountId = a.Id, LastName = 'Other');
    insert new List<Contact>{ original, other };
    List<Contact> cs = new List<Contact>();
    for (Integer i = 0; i < n; i++) {
      cs.add(
        new Contact(
          AccountId = a.Id,
          LastName = 'Guest ' + i,
          PMS_Possible_Duplicate_Of__c = original.Id,
          PMS_Duplicate_Reason__c = 'Same phone'
        )
      );
    }
    insert cs;
    return cs;
  }

  private static Contact reload(Id id) {
    return [
      SELECT Id, PMS_Possible_Duplicate_Of__c, PMS_Duplicate_Reason__c
      FROM Contact
      WHERE Id = :id
    ];
  }

  @isTest
  static void dismissingFlagClearsReason() {
    Contact c = flagged(1)[0];
    c.PMS_Possible_Duplicate_Of__c = null;
    update c;
    Contact r = reload(c.Id);
    Assert.isNull(r.PMS_Possible_Duplicate_Of__c);
    Assert.isNull(r.PMS_Duplicate_Reason__c);
  }

  @isTest
  static void changingToAnotherContactKeepsReason() {
    Contact c = flagged(1)[0];
    Contact other = [SELECT Id FROM Contact WHERE LastName = 'Other'];
    c.PMS_Possible_Duplicate_Of__c = other.Id;
    update c;
    Contact r = reload(c.Id);
    Assert.areEqual(other.Id, r.PMS_Possible_Duplicate_Of__c);
    Assert.areEqual('Same phone', r.PMS_Duplicate_Reason__c);
  }

  @isTest
  static void unrelatedEditKeepsReason() {
    Contact c = flagged(1)[0];
    c.FirstName = 'Changed';
    update c;
    Contact r = reload(c.Id);
    Assert.isNotNull(r.PMS_Possible_Duplicate_Of__c);
    Assert.areEqual('Same phone', r.PMS_Duplicate_Reason__c);
  }

  @isTest
  static void bulkDismissClearsAndOthersKept() {
    List<Contact> cs = flagged(200);
    for (Integer i = 0; i < cs.size(); i++) {
      if (Math.mod(i, 2) == 0) {
        cs[i].PMS_Possible_Duplicate_Of__c = null;
      } else {
        cs[i].FirstName = 'Edited';
      }
    }
    Test.startTest();
    update cs;
    Test.stopTest();
    Integer cleared = 0;
    Integer kept = 0;
    for (Contact r : [
      SELECT PMS_Possible_Duplicate_Of__c, PMS_Duplicate_Reason__c
      FROM Contact
      WHERE LastName LIKE 'Guest %'
    ]) {
      if (r.PMS_Possible_Duplicate_Of__c == null) {
        Assert.isNull(r.PMS_Duplicate_Reason__c);
        cleared++;
      } else {
        Assert.areEqual('Same phone', r.PMS_Duplicate_Reason__c);
        kept++;
      }
    }
    Assert.areEqual(100, cleared);
    Assert.areEqual(100, kept);
  }

  @isTest
  static void handlerToleratesNullInput() {
    PMS_ContactTriggerHandler.beforeUpdate(null, null);
    Assert.isTrue(true);
  }

  @isTest
  static void editorWithReadOnlyReasonCanDismiss() {
    Id ownerId = UserInfo.getUserId();
    User u = new User(
      Alias = 'g360ed',
      Email = 'g360ed@example.com',
      Username = 'g360ed' + System.currentTimeMillis() + '@example.com',
      LastName = 'Editor',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'GMT',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id
    );
    System.runAs(new User(Id = ownerId)) {
      insert u;
      List<PermissionSetAssignment> asg = new List<PermissionSetAssignment>();
      for (PermissionSet ps : [
        SELECT Id
        FROM PermissionSet
        WHERE Name IN ('PMS_Guest360_Viewer', 'PMS_Guest360_Editor')
      ]) {
        asg.add(
          new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = ps.Id
          )
        );
      }
      Assert.areEqual(
        2,
        asg.size(),
        'Both Guest 360 permission sets must exist'
      );
      insert asg;
    }
    Id contactId;
    System.runAs(u) {
      // Created by the editor so record sharing (private org-wide defaults) is not what is under test.
      contactId = flagged(1)[0].Id;
      Assert.isFalse(
        Schema.sObjectType.Contact.fields.PMS_Duplicate_Reason__c.isUpdateable(),
        'Reason must be read-only for the editor'
      );
      Contact c = new Contact(
        Id = contactId,
        PMS_Possible_Duplicate_Of__c = null
      );
      update as user c;
    }
    Contact r = reload(contactId);
    Assert.isNull(r.PMS_Possible_Duplicate_Of__c);
    Assert.isNull(r.PMS_Duplicate_Reason__c);
  }
}
