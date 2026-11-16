@isTest
private class PMS_HomeControllerAccessTest {
  static void assign(String permissionSetName) {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = :permissionSetName
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
  }

  @isTest
  static void stripAmountsRemovesMoney() {
    PMS_HomeController.HomeData d = new PMS_HomeController.HomeData();
    PMS_HomeController.Kpi money = new PMS_HomeController.Kpi();
    money.format = 'money';
    PMS_HomeController.Kpi count = new PMS_HomeController.Kpi();
    count.format = 'count';
    d.kpis.add(money);
    d.kpis.add(count);
    PMS_HomeController.Chart ch = new PMS_HomeController.Chart();
    ch.format = 'money';
    d.charts.add(ch);
    PMS_HomeController.Section s = new PMS_HomeController.Section();
    PMS_HomeController.Item i = new PMS_HomeController.Item();
    i.amount = 100;
    s.items.add(i);
    d.sections.add(s);
    PMS_HomeController.Item a = new PMS_HomeController.Item();
    a.amount = 5;
    d.agenda.add(a);

    PMS_HomeController.stripAmounts(d);

    Assert.areEqual(1, d.kpis.size());
    Assert.areEqual('count', d.kpis[0].format);
    Assert.isTrue(d.charts.isEmpty());
    Assert.isNull(d.sections[0].items[0].amount);
    Assert.isNull(d.agenda[0].amount);
  }

  @isTest
  static void adminHomeForAccessManagerWhoHidesAmounts() {
    assign('PMS_Access_Manager');
    assign('PMS_Hide_Amounts');
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PMS_TestDataFactory.hotel(1);
      Test.startTest();
      PMS_HomeController.HomeData d = PMS_HomeController.getHome('Admin', null);
      Test.stopTest();
      Assert.isTrue(
        d.canManageAccess,
        'access managers get the Access Setup action'
      );
      Assert.isTrue(d.hideAmounts, 'the Hide Amounts permission is picked up');
      Assert.isNotNull(
        d.accessNotice,
        'the Admin home says how far the rules are applied'
      );
      for (PMS_HomeController.Kpi k : d.kpis) {
        Assert.areNotEqual('money', k.format, 'no money tiles: ' + k.label);
      }
    }
  }

  @isTest
  static void moduleHomesIncludeNewQueues() {
    PMS_TestDataFactory.property();
    PMS_TestDataFactory.practice();
    Test.startTest();
    PMS_HomeController.HomeData p = PMS_HomeController.getHome(
      'Property',
      null
    );
    PMS_HomeController.HomeData pr = PMS_HomeController.getHome(
      'Practice',
      null
    );
    Test.stopTest();
    Set<String> pKeys = new Set<String>();
    for (PMS_HomeController.Section s : p.sections) {
      pKeys.add(s.key);
    }
    Set<String> prKeys = new Set<String>();
    for (PMS_HomeController.Section s : pr.sections) {
      prKeys.add(s.key);
    }
    Assert.isTrue(
      pKeys.contains('quotes'),
      'property shows vendor quotes: ' + p.warnings
    );
    Assert.isTrue(
      pKeys.contains('checkins'),
      'property shows tenant check-ins: ' + p.warnings
    );
    Assert.isTrue(
      prKeys.contains('checkins'),
      'practice shows questionnaires: ' + pr.warnings
    );
    Assert.isTrue(
      prKeys.contains('signatures'),
      'practice shows documents to sign: ' + pr.warnings
    );
    Assert.isNull(p.accessNotice, 'the access notice is Admin-home only');
  }
}
