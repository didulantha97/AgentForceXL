@isTest
private class PMS_OwnerStatementJobTest {
  private static List<PMS_Site__c> ownedSites(Integer n, Account owner) {
    List<PMS_Site__c> sites = new List<PMS_Site__c>();
    for (Integer i = 0; i < n; i++) {
      sites.add(
        new PMS_Site__c(
          Name = 'Owned Building ' + i,
          RecordTypeId = PMS_TestDataFactory.rt(
            PMS_Site__c.SObjectType,
            'Property'
          ),
          Module__c = 'Property',
          Status__c = 'Active',
          Time_Zone__c = 'Europe/Stockholm',
          Owner_Account__c = owner.Id,
          Management_Fee_Percent__c = 10
        )
      );
    }
    insert sites;
    return sites;
  }

  private static PMS_Vendor_Bill__c bill(
    Id siteId,
    Date billDate,
    Decimal amt
  ) {
    return new PMS_Vendor_Bill__c(
      Site__c = siteId,
      Amount__c = amt,
      Status__c = 'Approved',
      Bill_Date__c = billDate
    );
  }

  private static List<PMS_Owner_Statement__c> statements(Id siteId) {
    return [
      SELECT
        Id,
        Period_Start__c,
        Period_End__c,
        Status__c,
        Expenses__c,
        Owner_Account__c
      FROM PMS_Owner_Statement__c
      WHERE Site__c = :siteId
      ORDER BY Period_Start__c
    ];
  }

  @isTest
  static void midMonthRefreshesOnlyCurrentMonthDraftAndLinksBills() {
    Account owner = PMS_TestDataFactory.account('Owner AB');
    PMS_Site__c site = ownedSites(1, owner)[0];
    Date day = Date.newInstance(2026, 6, 15);
    PMS_Vendor_Bill__c inMonth = bill(
      site.Id,
      Date.newInstance(2026, 6, 10),
      400
    );
    PMS_Vendor_Bill__c prevMonth = bill(
      site.Id,
      Date.newInstance(2026, 5, 28),
      999
    );
    insert new List<PMS_Vendor_Bill__c>{ inMonth, prevMonth };

    Test.startTest();
    Database.executeBatch(new PMS_OwnerStatementJob(day), 10);
    Test.stopTest();

    List<PMS_Owner_Statement__c> sts = statements(site.Id);
    Assert.areEqual(1, sts.size(), 'day 15: current month only');
    Assert.areEqual(Date.newInstance(2026, 6, 1), sts[0].Period_Start__c);
    Assert.areEqual(Date.newInstance(2026, 6, 30), sts[0].Period_End__c);
    Assert.areEqual('Draft', sts[0].Status__c);
    Assert.areEqual(owner.Id, sts[0].Owner_Account__c);
    Assert.areEqual(400, sts[0].Expenses__c);
    Assert.areEqual(
      sts[0].Id,
      [SELECT Owner_Statement__c FROM PMS_Vendor_Bill__c WHERE Id = :inMonth.Id]
      .Owner_Statement__c,
      'in-period bill is linked to the statement'
    );
    Assert.isNull(
      [
        SELECT Owner_Statement__c
        FROM PMS_Vendor_Bill__c
        WHERE Id = :prevMonth.Id
      ]
      .Owner_Statement__c,
      'previous-month bill is not touched'
    );
  }

  @isTest
  static void firstFiveDaysAlsoRefreshPreviousMonth() {
    Account owner = PMS_TestDataFactory.account('Owner AB');
    PMS_Site__c site = ownedSites(1, owner)[0];
    insert new List<PMS_Vendor_Bill__c>{
      bill(site.Id, Date.newInstance(2026, 6, 2), 100),
      bill(site.Id, Date.newInstance(2026, 5, 30), 250)
    };

    Test.startTest();
    Database.executeBatch(
      new PMS_OwnerStatementJob(Date.newInstance(2026, 6, 5)),
      10
    );
    Test.stopTest();

    List<PMS_Owner_Statement__c> sts = statements(site.Id);
    Assert.areEqual(
      2,
      sts.size(),
      'day 5 is the last day that refreshes the previous month'
    );
    Assert.areEqual(Date.newInstance(2026, 5, 1), sts[0].Period_Start__c);
    Assert.areEqual(250, sts[0].Expenses__c);
    Assert.areEqual(Date.newInstance(2026, 6, 1), sts[1].Period_Start__c);
    Assert.areEqual(100, sts[1].Expenses__c);
  }

  @isTest
  static void daySixDoesNotTouchPreviousMonth() {
    PMS_Site__c site = ownedSites(
      1,
      PMS_TestDataFactory.account('Owner AB')
    )[0];
    Test.startTest();
    Database.executeBatch(
      new PMS_OwnerStatementJob(Date.newInstance(2026, 6, 6)),
      10
    );
    Test.stopTest();
    List<PMS_Owner_Statement__c> sts = statements(site.Id);
    Assert.areEqual(1, sts.size());
    Assert.areEqual(Date.newInstance(2026, 6, 1), sts[0].Period_Start__c);
  }

  @isTest
  static void publishedAndPaidStatementsAreFrozenDraftIsRefreshed() {
    Account owner = PMS_TestDataFactory.account('Owner AB');
    List<PMS_Site__c> sites = ownedSites(3, owner);
    Date june = Date.newInstance(2026, 6, 1);
    List<PMS_Owner_Statement__c> seed = new List<PMS_Owner_Statement__c>{
      new PMS_Owner_Statement__c(
        Site__c = sites[0].Id,
        Owner_Account__c = owner.Id,
        Period_Start__c = june,
        Period_End__c = june.addMonths(1).addDays(-1),
        Status__c = 'Published',
        Expenses__c = 1
      ),
      new PMS_Owner_Statement__c(
        Site__c = sites[1].Id,
        Owner_Account__c = owner.Id,
        Period_Start__c = june,
        Period_End__c = june.addMonths(1).addDays(-1),
        Status__c = 'Paid',
        Expenses__c = 2
      ),
      new PMS_Owner_Statement__c(
        Site__c = sites[2].Id,
        Owner_Account__c = owner.Id,
        Period_Start__c = june,
        Period_End__c = june.addMonths(1).addDays(-1),
        Status__c = 'Draft',
        Expenses__c = 3
      )
    };
    insert seed;
    List<PMS_Vendor_Bill__c> bills = new List<PMS_Vendor_Bill__c>();
    for (PMS_Site__c s : sites) {
      bills.add(bill(s.Id, Date.newInstance(2026, 6, 10), 50));
    }
    insert bills;

    Test.startTest();
    Database.executeBatch(
      new PMS_OwnerStatementJob(Date.newInstance(2026, 6, 20)),
      10
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      statements(sites[0].Id).size(),
      'no duplicate for published'
    );
    Assert.areEqual(
      1,
      statements(sites[0].Id)[0].Expenses__c,
      'published unchanged'
    );
    Assert.areEqual('Published', statements(sites[0].Id)[0].Status__c);
    Assert.areEqual(
      2,
      statements(sites[1].Id)[0].Expenses__c,
      'paid unchanged'
    );
    Assert.areEqual('Paid', statements(sites[1].Id)[0].Status__c);
    List<PMS_Owner_Statement__c> draft = statements(sites[2].Id);
    Assert.areEqual(1, draft.size(), 'draft updated in place, not duplicated');
    Assert.areEqual(seed[2].Id, draft[0].Id);
    Assert.areEqual(50, draft[0].Expenses__c, 'draft refreshed');
    Assert.isNull(
      [
        SELECT Owner_Statement__c
        FROM PMS_Vendor_Bill__c
        WHERE Id = :bills[0].Id
      ]
      .Owner_Statement__c,
      'bill of a frozen statement is not relinked'
    );
  }

  @isTest
  static void queryScopeSkipsInactiveAndOwnerlessSites() {
    Account owner = PMS_TestDataFactory.account('Owner AB');
    PMS_Site__c active = ownedSites(1, owner)[0];
    PMS_Site__c inactive = ownedSites(1, owner)[0];
    inactive.Status__c = 'Inactive';
    update inactive;
    PMS_Site__c noOwner = ownedSites(1, owner)[0];
    noOwner.Owner_Account__c = null;
    update noOwner;

    Test.startTest();
    Database.executeBatch(
      new PMS_OwnerStatementJob(Date.newInstance(2026, 6, 15)),
      10
    );
    Test.stopTest();

    Assert.areEqual(1, statements(active.Id).size());
    Assert.areEqual(0, statements(inactive.Id).size(), 'inactive site skipped');
    Assert.areEqual(
      0,
      statements(noOwner.Id).size(),
      'site without owner skipped'
    );
  }

  @isTest
  static void productionScopeOfTenSitesIsProcessedInOneChunk() {
    // The job runs with scope 10 (see execute(SchedulableContext)); each site costs ~6 SOQL, so 10 is the
    // largest chunk that fits the 100-query limit with the previous-month pass on days 1 to 5.
    Account owner = PMS_TestDataFactory.account('Owner AB');
    List<PMS_Site__c> sites = ownedSites(10, owner);
    List<PMS_Vendor_Bill__c> bills = new List<PMS_Vendor_Bill__c>();
    for (PMS_Site__c s : sites) {
      bills.add(bill(s.Id, Date.newInstance(2026, 6, 3), 10));
    }
    insert bills;

    Test.startTest();
    Database.executeBatch(
      new PMS_OwnerStatementJob(Date.newInstance(2026, 6, 3)),
      10
    );
    Test.stopTest();

    Assert.areEqual(
      20,
      [SELECT COUNT() FROM PMS_Owner_Statement__c WHERE Site__c IN :sites],
      'two months x 10 sites'
    );
    Assert.areEqual(
      10,
      [
        SELECT COUNT()
        FROM PMS_Owner_Statement__c
        WHERE
          Site__c IN :sites
          AND Period_Start__c = :Date.newInstance(2026, 6, 1)
          AND Expenses__c = 10
      ]
    );
  }

  @isTest
  static void rerunIsIdempotent() {
    PMS_Site__c site = ownedSites(
      1,
      PMS_TestDataFactory.account('Owner AB')
    )[0];
    insert bill(site.Id, Date.newInstance(2026, 6, 10), 70);
    Test.startTest();
    Database.executeBatch(
      new PMS_OwnerStatementJob(Date.newInstance(2026, 6, 15)),
      10
    );
    Test.stopTest();
    Id first = statements(site.Id)[0].Id;
    new PMS_OwnerStatementJob(Date.newInstance(2026, 6, 16))
      .execute((Database.BatchableContext) null, new List<PMS_Site__c>{ site });
    List<PMS_Owner_Statement__c> after = statements(site.Id);
    Assert.areEqual(1, after.size());
    Assert.areEqual(first, after[0].Id);
  }

  @isTest
  static void schedulableRunsBatchWhenLicensed() {
    PMS_Site__c site = ownedSites(
      1,
      PMS_TestDataFactory.account('Owner AB')
    )[0];
    Test.startTest();
    new PMS_OwnerStatementJob().execute((SchedulableContext) null);
    Test.stopTest();
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'PMS_OwnerStatementJob' AND JobType = 'BatchApex'
      ],
      'batch enqueued'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Owner_Statement__c
        WHERE
          Site__c = :site.Id
          AND Period_Start__c = :Date.today().toStartOfMonth()
      ]
    );
  }

  @isTest
  static void schedulableSkipsWhenLicenceSuspended() {
    PMS_Site__c site = ownedSites(
      1,
      PMS_TestDataFactory.account('Owner AB')
    )[0];
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    Test.startTest();
    new PMS_OwnerStatementJob().execute((SchedulableContext) null);
    Test.stopTest();
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'PMS_OwnerStatementJob' AND JobType = 'BatchApex'
      ],
      'no batch while suspended'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Owner_Statement__c WHERE Site__c = :site.Id]
    );
  }

  @isTest
  static void scheduleNightlyRegistersCronAt0330() {
    Test.startTest();
    Id jobId = PMS_OwnerStatementJob.scheduleNightly();
    Test.stopTest();
    CronTrigger ct = [
      SELECT CronExpression, CronJobDetail.Name, State
      FROM CronTrigger
      WHERE Id = :jobId
    ];
    Assert.areEqual('0 30 3 * * ?', ct.CronExpression);
    Assert.areEqual(PMS_OwnerStatementJob.JOB_NAME, ct.CronJobDetail.Name);
  }

  @isTest
  static void defaultConstructorUsesToday() {
    Assert.areEqual(Date.today(), new PMS_OwnerStatementJob().today);
    Assert.areEqual(
      Date.newInstance(2026, 1, 2),
      new PMS_OwnerStatementJob(Date.newInstance(2026, 1, 2)).today
    );
  }

  @isTest
  static void generateForDayAtScaleHandsOffToBatchInsteadOfBlowingLimits() {
    Account owner = PMS_TestDataFactory.account('Owner AB');
    // Apex tests cannot run a batch over more than one chunk, so lower the inline limit instead of creating 40 sites.
    PMS_OwnerStatementService.INLINE_SITE_LIMIT = 3;
    Integer n = PMS_OwnerStatementService.INLINE_SITE_LIMIT + 4;
    List<PMS_Site__c> sites = ownedSites(n, owner);
    Date day = Date.newInstance(2026, 6, 3); // day <= 5: batch must not add a previous-month statement

    Integer result;
    Test.startTest();
    result = PMS_OwnerStatementService.generate(day);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Owner_Statement__c],
      'nothing inline above the limit'
    );
    Test.stopTest();

    Assert.areEqual(n, result, 'returns sites queued');
    Assert.areEqual(
      n,
      [
        SELECT COUNT()
        FROM PMS_Owner_Statement__c
        WHERE Period_Start__c = :Date.newInstance(2026, 6, 1)
      ]
    );
    Assert.areEqual(
      n,
      [SELECT COUNT() FROM PMS_Owner_Statement__c],
      'current month only'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'PMS_OwnerStatementJob' AND JobType = 'BatchApex'
      ]
    );
  }

  @isTest
  static void generateForDayBelowLimitRunsInline() {
    Account owner = PMS_TestDataFactory.account('Owner AB');
    ownedSites(3, owner);
    Assert.areEqual(
      3,
      PMS_OwnerStatementService.generate(Date.newInstance(2026, 6, 15))
    );
    Assert.areEqual(3, [SELECT COUNT() FROM PMS_Owner_Statement__c]);
  }

  @isTest
  static void activeJobAlreadyQueuedGivesPartialInlineRunAndNoSecondEnqueue() {
    Account owner = PMS_TestDataFactory.account('Owner AB');
    PMS_OwnerStatementService.INLINE_SITE_LIMIT = 3;
    List<PMS_Site__c> sites = ownedSites(5, owner);
    Date day = Date.newInstance(2026, 6, 15);

    Test.startTest();
    Database.executeBatch(new PMS_OwnerStatementJob(day), 10); // already queued, not yet run
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'PMS_OwnerStatementJob' AND JobType = 'BatchApex'
      ]
    );

    Integer result = PMS_OwnerStatementService.generate(day);

    Assert.areEqual(
      3,
      result,
      'partial: only the first INLINE_SITE_LIMIT sites are refreshed inline'
    );
    Assert.areEqual(
      3,
      [SELECT COUNT() FROM PMS_Owner_Statement__c],
      'inline slice only'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'PMS_OwnerStatementJob' AND JobType = 'BatchApex'
      ],
      'no second batch enqueued'
    );
    // the slice is ordered by Id
    List<Id> ids = new List<Id>();
    for (PMS_Site__c s : sites) {
      ids.add(s.Id);
    }
    ids.sort();
    Set<Id> expected = new Set<Id>{ ids[0], ids[1], ids[2] };
    for (PMS_Owner_Statement__c st : [
      SELECT Site__c
      FROM PMS_Owner_Statement__c
    ]) {
      Assert.isTrue(
        expected.contains(st.Site__c),
        'statement belongs to one of the first three sites by Id'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void exactlyAtInlineLimitRunsInlineWithoutBatch() {
    PMS_OwnerStatementService.INLINE_SITE_LIMIT = 3;
    ownedSites(3, PMS_TestDataFactory.account('Owner AB'));
    Test.startTest();
    Integer result = PMS_OwnerStatementService.generate(
      Date.newInstance(2026, 6, 15)
    );
    Test.stopTest();
    Assert.areEqual(3, result);
    Assert.areEqual(3, [SELECT COUNT() FROM PMS_Owner_Statement__c]);
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'PMS_OwnerStatementJob' AND JobType = 'BatchApex'
      ]
    );
  }

  @isTest
  static void oneOverInlineLimitQueuesBatchAndReportsRealCountNotProbeCap() {
    // probe query is capped at limit + 1 (= 4); the return value must be the true number of sites (6)
    PMS_OwnerStatementService.INLINE_SITE_LIMIT = 3;
    ownedSites(6, PMS_TestDataFactory.account('Owner AB'));
    Integer result;
    Test.startTest();
    result = PMS_OwnerStatementService.generate(Date.newInstance(2026, 6, 15));
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Owner_Statement__c],
      'nothing inline'
    );
    Test.stopTest();
    Assert.areEqual(6, result, 'real count, not the capped probe size');
    Assert.areEqual(6, [SELECT COUNT() FROM PMS_Owner_Statement__c]);
  }
}
