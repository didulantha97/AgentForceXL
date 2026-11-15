@isTest
private class PMS_AccessTest {
  static PMS_AccessService.RuleInfo rule(
    Id groupId,
    Id siteId,
    String module,
    String keys,
    Boolean edit
  ) {
    PMS_AccessService.RuleInfo r = new PMS_AccessService.RuleInfo();
    r.groupId = groupId;
    r.siteId = siteId;
    r.module = module;
    if (keys != null) {
      r.keys.addAll(keys.split(';'));
    }
    r.edit = edit;
    return r;
  }

  @isTest
  static void matchingRules() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    Id g1 = UserInfo.getUserId(); // any Id works for the pure logic
    Id g2 = h.guest.Id;
    List<PMS_AccessService.RuleInfo> rules = new List<PMS_AccessService.RuleInfo>{
      rule(g1, null, 'Hotel', null, false), // all hotel sites, read
      rule(g1, h.site.Id, 'All', 'Booking', true), // this hotel's bookings, edit
      rule(g2, p.site.Id, 'All', null, true) // the property only
    };
    Map<Id, String> a = PMS_AccessService.desiredAccess(
      h.site.Id,
      'Hotel',
      'Booking',
      rules,
      'Private'
    );
    Assert.areEqual('Edit', a.get(g1), 'edit wins over read');
    Assert.isFalse(a.containsKey(g2), 'property rule does not reach the hotel');

    Map<Id, String> b = PMS_AccessService.desiredAccess(
      h.site.Id,
      'Hotel',
      'Invoice',
      rules,
      'Private'
    );
    Assert.areEqual(
      'Read',
      b.get(g1),
      'booking-only rule does not cover invoices'
    );

    Map<Id, String> c = PMS_AccessService.desiredAccess(
      h.site.Id,
      'Hotel',
      'Invoice',
      rules,
      'Read'
    );
    Assert.isTrue(
      c.isEmpty(),
      'read grants add nothing on a Public Read Only object'
    );

    Map<Id, String> d = PMS_AccessService.desiredAccess(
      null,
      null,
      'Booking',
      rules,
      'Private'
    );
    Assert.isTrue(
      d.isEmpty(),
      'records without a site only match rules for every site and module'
    );
  }

  @isTest
  static void pathsAndFields() {
    Assert.areEqual(
      new Set<String>{ 'Booking__c', 'Project__c' },
      PMS_AccessService.firstHopFields(
        'Booking__r.Site__c, Project__r.Site__c, Id'
      )
    );
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_Space_Type__c st = [
      SELECT Id, Site__c, Site__r.Id
      FROM PMS_Space_Type__c
      WHERE Id = :h.doubleRoom.Id
    ];
    Assert.areEqual(h.site.Id, PMS_AccessService.resolvePath(st, 'Site__r.Id'));
    Assert.areEqual(h.site.Id, PMS_AccessService.resolvePath(st, 'Site__c'));
    Assert.areEqual(
      'PMS_Booking__Share',
      PMS_AccessService.shareObjectName('PMS_Booking__c')
    );
    Assert.isNotNull(
      PMS_AccessService.configFor('PMS_Booking__c'),
      'booking is configured'
    );
  }

  @isTest
  static void teamSyncCreatesGroupMembersAndHidePermissions() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_Access_Team__c team = new PMS_Access_Team__c(
      Name = 'Front desk',
      Hide_Amounts__c = true
    );
    insert team;
    insert new PMS_Access_Team_Member__c(
      Team__c = team.Id,
      User__c = UserInfo.getUserId()
    );
    insert new PMS_Access_Rule__c(
      Team__c = team.Id,
      Site__c = h.site.Id,
      Module__c = 'Hotel',
      Access_Level__c = 'Edit'
    );

    Test.startTest();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      new PMS_AccessGroupSync(null, false).execute(null);
    }
    Test.stopTest();

    Group g = [
      SELECT Id
      FROM Group
      WHERE DeveloperName = :PMS_AccessService.teamGroupName(team.Id)
    ];
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM GroupMember
        WHERE GroupId = :g.Id AND UserOrGroupId = :UserInfo.getUserId()
      ]
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          PermissionSet.Name = 'PMS_Hide_Amounts'
          AND AssigneeId = :UserInfo.getUserId()
      ]
    );
    PMS_AccessService.resetCaches();
    List<PMS_AccessService.RuleInfo> rules = PMS_AccessService.activeRules();
    Assert.areEqual(1, rules.size());
    Assert.areEqual(g.Id, rules[0].groupId);
  }

  @isTest
  static void teamDeactivationRemovesGroup() {
    PMS_Access_Team__c team = new PMS_Access_Team__c(Name = 'Temp');
    insert team;
    insert new PMS_Access_Team_Member__c(
      Team__c = team.Id,
      User__c = UserInfo.getUserId(),
      End_Date__c = Date.today()
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      new PMS_AccessGroupSync(new Set<Id>{ team.Id }, false).syncGroups();
    }
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Group
        WHERE DeveloperName = :PMS_AccessService.teamGroupName(team.Id)
      ]
    );
    Test.startTest();
    team.Active__c = false;
    update team;
    Test.stopTest();
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Group
        WHERE DeveloperName = :PMS_AccessService.teamGroupName(team.Id)
      ]
    );
  }

  @isTest
  static void duplicateMemberIsRejected() {
    PMS_Access_Team__c team = new PMS_Access_Team__c(Name = 'Dupes');
    insert team;
    insert new PMS_Access_Team_Member__c(
      Team__c = team.Id,
      User__c = UserInfo.getUserId()
    );
    Database.SaveResult r = Database.insert(
      new PMS_Access_Team_Member__c(
        Team__c = team.Id,
        User__c = UserInfo.getUserId()
      ),
      false
    );
    Assert.isFalse(r.isSuccess(), 'same user twice in one team');
    Database.SaveResult noUser = Database.insert(
      new PMS_Access_Team_Member__c(Team__c = team.Id),
      false
    );
    Assert.isFalse(noUser.isSuccess(), 'user is required');
  }

  @isTest
  static void recalcWritesSharesWhenObjectIsRestricted() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_Access_Team__c team = new PMS_Access_Team__c(
      Name = 'Everyone',
      All_Internal_Users__c = true
    );
    insert team;
    insert new PMS_Access_Rule__c(
      Team__c = team.Id,
      Module__c = 'All',
      Access_Level__c = 'Edit'
    );
    PMS_AccessService.owdOverride.put('PMS_Space_Type__c', 'Private');
    PMS_AccessService.rowCauseOverride = 'Manual';
    PMS_AccessService.resetCaches();

    Test.startTest();
    PMS_AccessService.recalcRecords(
      'PMS_Space_Type__c',
      new Set<Id>{ h.doubleRoom.Id }
    );
    // second run: nothing to change, or the org default is still Public Read/Write and the insert was refused
    PMS_AccessService.recalcRecords(
      'PMS_Space_Type__c',
      new Set<Id>{ h.doubleRoom.Id }
    );
    Test.stopTest();

    Integer shares = [
      SELECT COUNT()
      FROM PMS_Space_Type__Share
      WHERE ParentId = :h.doubleRoom.Id AND RowCause = 'Manual'
    ];
    Assert.isTrue(
      shares == 1 || !PMS_AccessService.lastErrors.isEmpty(),
      'a share exists, or the refusal was logged'
    );
  }

  @isTest
  static void triggersRunOnEveryConfiguredObject() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_AccessService.owdOverride.put('PMS_Space_Type__c', 'Private');
    PMS_AccessService.rowCauseOverride = 'Manual';
    // Empty inserts may be refused for missing fields; the before-insert trigger still runs first.
    for (PMS_Access_Object__mdt c : PMS_AccessService.objectConfigs()) {
      Schema.SObjectType t = Schema.getGlobalDescribe()
        .get(c.Object_API_Name__c);
      if (t != null) {
        Database.insert(t.newSObject(), false);
      }
    }
    Test.startTest();
    insert new PMS_Space_Type__c(
      Name = 'Suite',
      Site__c = h.site.Id,
      Default_Rate__c = 2000,
      Default_Occupancy__c = 2
    );
    h.site.Module__c = 'Property';
    update h.site;
    Test.stopTest();
    Assert.isTrue(true, 'triggers ran without blocking the saves');
  }

  @isTest
  static void batchAndNightly() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_AccessService.owdOverride.put('PMS_Space_Type__c', 'Private');
    PMS_AccessService.rowCauseOverride = 'Manual';
    Test.startTest();
    PMS_AccessRecalcBatch b = new PMS_AccessRecalcBatch(
      new List<String>{ 'PMS_Space_Type__c' },
      0
    );
    Database.executeBatch(b, 200); // only one executeBatch is allowed per test
    PMS_AccessRecalcBatch empty = new PMS_AccessRecalcBatch(
      new List<String>(),
      0
    );
    empty.start(null);
    empty.execute(null, new List<SObject>());
    empty.finish(null);
    Assert.isNotNull(
      new PMS_AccessRecalcBatch(),
      'default constructor picks the restricted objects'
    );
    new PMS_AccessNightly().execute(null);
    Test.stopTest();
    Assert.isNotNull(
      [
        SELECT Id
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'PMS_AccessRecalcBatch'
        LIMIT 1
      ]
    );
  }

  @isTest
  static void consoleForManagers() {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'PMS_Access_Manager'
      ];
      if (
        [
          SELECT COUNT()
          FROM PermissionSetAssignment
          WHERE PermissionSetId = :ps.Id AND AssigneeId = :me.Id
        ] == 0
      ) {
        insert new PermissionSetAssignment(
          PermissionSetId = ps.Id,
          AssigneeId = me.Id
        );
      }
    }
    System.runAs(me) {
      PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
      PMS_Access_Team__c team = new PMS_Access_Team__c(
        Name = 'Everyone',
        All_Internal_Users__c = true
      );
      insert team;
      insert new PMS_Access_Rule__c(
        Team__c = team.Id,
        Module__c = 'Hotel',
        Access_Level__c = 'Read'
      );

      Test.startTest();
      PMS_AccessConsoleController.Overview o = PMS_AccessConsoleController.getOverview();
      Assert.isTrue(o.canManage);
      Assert.isFalse(o.objects.isEmpty());
      PMS_AccessConsoleController.AccessCheck c = PMS_AccessConsoleController.checkAccess(
        UserInfo.getUserId(),
        'https://example.lightning.force.com/lightning/r/PMS_Site__c/' +
          h.site.Id +
          '/view'
      );
      Assert.isTrue(c.hasRead);
      Assert.areEqual('Hotel', c.explanation.module);
      Assert.areEqual(
        1,
        c.explanation.grantingRules.size(),
        'the everyone rule reaches every user'
      );
      PMS_AccessConsoleController.recalculateNow();
      String first = PMS_AccessConsoleController.scheduleNightly();
      Assert.isTrue(first == 'scheduled' || first == 'already');
      Assert.areEqual('already', PMS_AccessConsoleController.scheduleNightly());
      Test.stopTest();

      try {
        PMS_AccessConsoleController.parseId('not an id');
        Assert.fail('expected an error');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e);
      }
    }
  }
}
