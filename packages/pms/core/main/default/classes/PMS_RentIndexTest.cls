@isTest
private class PMS_RentIndexTest {
  private static Integer unitNo = 0;

  private static PMS_Booking__c lease(
    String leaseType,
    Date startDate,
    Date endDate,
    Decimal rent,
    Boolean indexed
  ) {
    PMS_Site__c site = [
      SELECT Id
      FROM PMS_Site__c
      WHERE Module__c = 'Property'
      LIMIT 1
    ];
    unitNo++;
    PMS_Space__c unit = new PMS_Space__c(
      Name = 'U-' + unitNo,
      RecordTypeId = PMS_TestDataFactory.rt(PMS_Space__c.SObjectType, 'Unit'),
      Site__c = site.Id,
      Base_Rate__c = rent,
      Bookable__c = true,
      Operational_Status__c = 'Available'
    );
    insert unit;
    Account a = new Account(Name = 'Tenant ' + unitNo);
    insert a;
    Contact c = new Contact(
      AccountId = a.Id,
      LastName = 'Tenant',
      FirstName = 'Tess',
      Email = 'tenant' + unitNo + '@example.com'
    );
    insert c;
    PMS_Booking__c b = new PMS_Booking__c(
      RecordTypeId = PMS_TestDataFactory.rt(
        PMS_Booking__c.SObjectType,
        'Lease'
      ),
      Site__c = site.Id,
      Space__c = unit.Id,
      Account__c = a.Id,
      Primary_Contact__c = c.Id,
      Start__c = Datetime.newInstance(startDate, Time.newInstance(12, 0, 0, 0)),
      End__c = Datetime.newInstance(endDate, Time.newInstance(12, 0, 0, 0)),
      Status__c = 'Active',
      Lease_Type__c = leaseType,
      Rate_Amount__c = rent,
      Rent_Frequency__c = 'Monthly',
      Index_Clause__c = indexed,
      Index_Series__c = 'KPI 1980=100',
      Index_Base_Value__c = indexed ? 400 : null,
      Index_Base_Rent__c = indexed ? rent : null,
      Index_Share__c = indexed ? 100 : null
    );
    insert b;
    return b;
  }

  private static Integer nextYear() {
    return Date.today().year() + 1;
  }

  @TestSetup
  static void setup() {
    PMS_TestDataFactory.property();
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'PMS_Rent_Review'
      ];
      if (
        [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE PermissionSetId = :ps.Id AND AssigneeId = :me.Id
          ]
          .isEmpty()
      ) {
        insert new PermissionSetAssignment(
          PermissionSetId = ps.Id,
          AssigneeId = me.Id
        );
      }
    }
  }

  @isTest
  static void indexArithmetic() {
    PMS_TestDataFactory.num(
      24600,
      PMS_RentIndexService.indexedRent(24000, 400, 410, 100, false),
      'up with the index'
    );
    PMS_TestDataFactory.num(
      24000,
      PMS_RentIndexService.indexedRent(24000, 400, 390, 100, false),
      'never below base'
    );
    PMS_TestDataFactory.num(
      23400,
      PMS_RentIndexService.indexedRent(24000, 400, 390, 100, true),
      'below base when the clause allows'
    );
    PMS_TestDataFactory.num(
      24480,
      PMS_RentIndexService.indexedRent(24000, 400, 410, 80, false),
      '80% indexed share'
    );
    PMS_TestDataFactory.num(
      2.5,
      PMS_RentIndexService.changePercent(24000, 24600),
      'change %'
    );
    Assert.isNull(PMS_RentIndexService.changePercent(0, 100));
    Assert.areEqual('abc...', PMS_RentIndexService.cut('abcdefgh', 6));
  }

  @isTest
  static void indexAdjustmentsRespectTheThreeYearRule() {
    Integer y = nextYear();
    insert new PMS_Index_Value__c(
      Series__c = 'KPI 1980=100',
      Year__c = y - 1,
      Month__c = 10,
      Value__c = 410,
      Source__c = 'test'
    );
    PMS_Booking__c longLease = lease(
      'Commercial',
      Date.newInstance(y - 3, 1, 1),
      Date.newInstance(y + 1, 12, 31),
      24000,
      true
    );
    PMS_Booking__c shortLease = lease(
      'Commercial',
      Date.newInstance(y - 1, 1, 1),
      Date.newInstance(y, 12, 31),
      15000,
      true
    );
    Assert.isTrue(
      PMS_RentIndexService.termAtLeastThreeYears(
        [SELECT Start__c, End__c FROM PMS_Booking__c WHERE Id = :longLease.Id]
      )
    );
    Assert.isFalse(
      PMS_RentIndexService.termAtLeastThreeYears(
        [SELECT Start__c, End__c FROM PMS_Booking__c WHERE Id = :shortLease.Id]
      )
    );

    PMS_RentIndexService.Result r = PMS_RentIndexService.prepareIndex(y, null);
    Assert.areEqual(1, r.created, String.join(r.messages, ' | '));
    PMS_Rent_Adjustment__c a = [
      SELECT
        Lease__c,
        Kind__c,
        Status__c,
        New_Rent__c,
        Change_Percent__c,
        Effective_Date__c,
        Index_Period__c
      FROM PMS_Rent_Adjustment__c
    ];
    Assert.areEqual(longLease.Id, a.Lease__c);
    Assert.areEqual('Draft', a.Status__c);
    Assert.areEqual(Date.newInstance(y, 1, 1), a.Effective_Date__c);
    PMS_TestDataFactory.num(24600, a.New_Rent__c, 'indexed rent');
    PMS_TestDataFactory.num(2.5, a.Change_Percent__c, 'change');
    Assert.isTrue(
      String.join(r.messages, ' ').contains('three years'),
      String.join(r.messages, ' | ')
    );

    PMS_RentIndexService.Result again = PMS_RentIndexService.prepareIndex(
      y,
      null
    );
    Assert.areEqual(0, again.created, 'no duplicates');
    PMS_RentIndexService.Result missing = PMS_RentIndexService.prepareIndex(
      y + 1,
      null
    );
    Assert.areEqual(0, missing.created);
    Assert.isTrue(
      String.join(missing.messages, ' ').contains('missing'),
      String.join(missing.messages, ' | ')
    );
  }

  @isTest
  static void negotiatedIncreaseNoticeAndApply() {
    Integer y = nextYear();
    PMS_Booking__c res = lease(
      'Residential',
      Date.newInstance(y - 2, 3, 1),
      Date.newInstance(y + 2, 2, 28),
      10000,
      false
    );
    insert new PMS_Lease_Charge_Schedule__c(
      Lease__c = res.Id,
      Charge_Type__c = 'Rent',
      Amount__c = 10000,
      Frequency__c = 'Monthly',
      Start_Date__c = Date.newInstance(y - 2, 3, 1),
      Next_Run_Date__c = Date.newInstance(y + 5, 1, 1),
      Active__c = true
    );
    Date effective = Date.newInstance(y, 4, 1);
    PMS_RentIndexService.Result r = PMS_RentIndexService.prepareNegotiated(
      null,
      2.5,
      effective,
      'As agreed with Hyresgästföreningen.'
    );
    Assert.areEqual(1, r.created, String.join(r.messages, ' | '));
    PMS_Rent_Adjustment__c a = [
      SELECT Id, New_Rent__c
      FROM PMS_Rent_Adjustment__c
    ];
    PMS_TestDataFactory.num(10250, a.New_Rent__c, 'negotiated rent');

    Assert.areEqual(1, PMS_RentIndexService.approve(new Set<Id>{ a.Id }));
    List<String> sent = PMS_RentIndexService.sendNotices(new Set<Id>{ a.Id });
    Assert.isTrue(sent[0].contains('notice sent'), sent[0]);
    Assert.areEqual(
      'Notice Sent',
      [SELECT Status__c FROM PMS_Rent_Adjustment__c WHERE Id = :a.Id].Status__c
    );

    Assert.areEqual(
      0,
      PMS_RentIndexService.applyDue(effective.addDays(-1)),
      'not before the effective date'
    );
    Assert.areEqual(1, PMS_RentIndexService.applyDue(effective));
    PMS_Booking__c after = [
      SELECT Rate_Amount__c, Last_Rent_Adjustment__c
      FROM PMS_Booking__c
      WHERE Id = :res.Id
    ];
    PMS_TestDataFactory.num(10250, after.Rate_Amount__c, 'lease rent');
    Assert.areEqual(effective, after.Last_Rent_Adjustment__c);
    PMS_TestDataFactory.num(
      10250,
      [
        SELECT Amount__c
        FROM PMS_Lease_Charge_Schedule__c
        WHERE Lease__c = :res.Id AND Charge_Type__c = 'Rent'
        ORDER BY CreatedDate DESC
        LIMIT 1
      ]
      .Amount__c,
      'rent schedule'
    );
    Assert.areEqual(
      'Applied',
      [SELECT Status__c FROM PMS_Rent_Adjustment__c WHERE Id = :a.Id].Status__c
    );

    PMS_RentIndexService.Result dup = PMS_RentIndexService.prepareNegotiated(
      null,
      2.5,
      effective,
      null
    );
    Assert.areEqual(0, dup.created);
  }

  @isTest
  static void reviewTabActions() {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      Integer y = nextYear();
      PMS_RentReviewController.saveIndexValue(
        'KPI 1980=100',
        y - 1,
        10,
        405,
        'SCB'
      );
      PMS_RentReviewController.saveIndexValue(
        'KPI 1980=100',
        y - 1,
        10,
        410,
        'SCB corrected'
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM PMS_Index_Value__c],
        'one value per series and month'
      );
      PMS_TestDataFactory.num(
        410,
        PMS_RentIndexService.indexValue('KPI 1980=100', y - 1, 10),
        'latest value'
      );

      lease(
        'Commercial',
        Date.newInstance(y - 3, 1, 1),
        Date.newInstance(y + 2, 12, 31),
        20000,
        true
      );
      PMS_RentIndexService.Result r = PMS_RentReviewController.prepareIndex(
        y,
        ''
      );
      Assert.areEqual(1, r.created, String.join(r.messages, ' | '));
      PMS_RentReviewController.Data d = PMS_RentReviewController.load(y);
      Assert.areEqual(1, d.rows.size());
      Assert.isTrue(d.sites.size() >= 2);
      Id adjId = d.rows[0].id;

      PMS_RentReviewController.updateNewRent(adjId, 20600);
      PMS_TestDataFactory.num(
        3,
        [SELECT Change_Percent__c FROM PMS_Rent_Adjustment__c WHERE Id = :adjId]
        .Change_Percent__c,
        'edited change'
      );
      Assert.areEqual(
        1,
        PMS_RentReviewController.approve(new List<Id>{ adjId })
      );
      try {
        PMS_RentReviewController.updateNewRent(adjId, 21000);
        Assert.fail('approved adjustments cannot be edited');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('draft'), e.getMessage());
      }
      List<String> lines = PMS_RentReviewController.sendNotices(
        new List<Id>{ adjId }
      );
      Assert.areEqual(1, lines.size());
      Assert.areEqual(
        1,
        PMS_RentReviewController.cancel(new List<Id>{ adjId })
      );
      try {
        PMS_RentReviewController.saveIndexValue('KPI 1980=100', y, 13, 1, null);
        Assert.fail('month 13 is invalid');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('month'), e.getMessage());
      }
    }
  }

  @isTest
  static void dailyJobApplies() {
    Integer y = Date.today().year();
    PMS_Booking__c res = lease(
      'Residential',
      Date.newInstance(y - 2, 1, 1),
      Date.newInstance(y + 2, 1, 1),
      8000,
      false
    );
    insert new PMS_Rent_Adjustment__c(
      Lease__c = res.Id,
      Kind__c = 'Manual',
      Status__c = 'Approved',
      Effective_Date__c = Date.today(),
      Old_Rent__c = 8000,
      New_Rent__c = 8400
    );
    Test.startTest();
    String jobId = System.schedule(
      'PMS Rent Adjustments test',
      '0 15 4 * * ?',
      new PMS_RentAdjustmentJob()
    );
    new PMS_RentAdjustmentJob().execute(null);
    Test.stopTest();
    Assert.isNotNull(jobId);
    PMS_TestDataFactory.num(
      8400,
      [SELECT Rate_Amount__c FROM PMS_Booking__c WHERE Id = :res.Id]
      .Rate_Amount__c,
      'applied by the job'
    );
  }
}
