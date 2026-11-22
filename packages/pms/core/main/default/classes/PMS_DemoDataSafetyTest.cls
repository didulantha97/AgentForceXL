/**
 * Safety tests for the demo data loader: the Developer Edition / trial opt-in, failure markers for dependent packs,
 * governor headroom of the batched steps, reset safety, and the side-effect guards on demo records.
 * Nothing here needs the baseline in @testSetup, so the heavy limits test starts from an empty org.
 */
@IsTest
private class PMS_DemoDataSafetyTest {
  private static void admin(String env) {
    PMS_DemoData.envOverride = env;
    PMS_DemoData.adminOverride = true;
    PMS_DemoData.optInOverride = null;
    PMS_DemoData.failAt = null;
  }

  private static PMS_Demo_Record__c marker(String pack, String prefix) {
    return new PMS_Demo_Record__c(
      Name = prefix + pack,
      Pack__c = pack,
      Record_Id__c = (prefix + pack).left(18),
      Object_Name__c = 'marker'
    );
  }

  private static PMS_Demo_Record__c row(
    String pack,
    Id recordId,
    String objectName,
    Integer seq
  ) {
    return new PMS_Demo_Record__c(
      Name = 'k.' + recordId,
      Pack__c = pack,
      Record_Id__c = String.valueOf(recordId),
      Object_Name__c = objectName,
      Sequence__c = seq
    );
  }

  private static PMS_DemoData.PackInfo pack(String key) {
    for (PMS_DemoData.PackInfo p : PMS_DemoData.status().packs) {
      if (p.key == key) {
        return p;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ S1 opt-in for Developer Edition / trial orgs

  @IsTest
  static void sandboxAndScratchOrgsNeedNoOptIn() {
    admin('allow');
    Assert.isNull(PMS_DemoData.optInProblem());
    Assert.isNull(PMS_DemoData.blockReason());
    Assert.isFalse(PMS_DemoData.status().optInRequired);
  }

  @IsTest
  static void developerEditionAndTrialOrgsNeedTheOptIn() {
    admin('optin');
    String reason = PMS_DemoData.blockReason();
    Assert.areEqual(PMS_DemoData.OPT_IN_MESSAGE, reason);
    Assert.isTrue(
      PMS_DemoData.load('baseline')
        .startsWith('Refused: This is a Developer Edition or trial org')
    );
    Assert.isTrue(PMS_DemoData.reset('all').startsWith('Refused'));
    PMS_DemoData.Status st = PMS_DemoDataController.getStatus();
    Assert.isFalse(st.allowed, 'nothing can run');
    Assert.isTrue(st.optInRequired, 'the card explains what to do');
    Assert.isTrue(st.reason.contains('Demo Data Allowed'), st.reason);
    Assert.isTrue(
      PMS_DemoDataController.load('baseline').message.startsWith('Refused')
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Demo_Record__c],
      'nothing was written'
    );

    PMS_DemoData.optInOverride = true;
    Assert.isNull(PMS_DemoData.blockReason());
    Assert.isTrue(PMS_DemoData.status().allowed);
  }

  @IsTest
  static void theOptInIsReadFromTheOrgDefaultSetting() {
    admin('optin');
    Assert.isNotNull(PMS_DemoData.optInProblem(), 'default is off');
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Demo_Data_Allowed__c = true
    );
    Assert.isNull(
      PMS_DemoData.optInProblem(),
      'ticked on the org default record'
    );
    Assert.isNull(PMS_DemoData.blockReason());
  }

  @IsTest
  static void nonAdminsInATrialOrgAreToldAboutAdminsNotTheOptIn() {
    admin('optin');
    PMS_DemoData.adminOverride = false;
    Assert.isTrue(PMS_DemoData.blockReason().contains('administrators'));
    Assert.isFalse(
      PMS_DemoData.status().optInRequired,
      'only admins see the opt-in card'
    );
  }

  @IsTest
  static void productionIsRefusedEvenWithTheOptIn() {
    admin('deny');
    PMS_DemoData.optInOverride = true;
    Assert.isTrue(PMS_DemoData.blockReason().contains('production'));
  }

  // ------------------------------------------------------------------ S3 dependent pack after a failed baseline

  @IsTest
  static void aBaselineFailureFailsTheDependentPackToo() {
    admin('allow');
    insert new List<PMS_Demo_Record__c>{
      marker('baseline', 'START:'),
      marker('overdue-wave', 'START:')
    };
    PMS_DemoData.failAt = 'core';
    List<String> plan = new List<String>{
      'baseline:core',
      'baseline:hotel',
      'overdue-wave:wave'
    };
    Assert.isFalse(PMS_DemoData.runStep(plan, 0));
    PMS_DemoData.failAt = null;
    Assert.areEqual(PMS_DemoData.FAILED, pack('baseline').state);
    PMS_DemoData.PackInfo wave = pack('overdue-wave');
    Assert.areEqual(
      PMS_DemoData.FAILED,
      wave.state,
      'not stuck in RUNNING: ' + wave.message
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Demo_Record__c
        WHERE Pack__c = 'overdue-wave' AND Record_Id__c LIKE 'ERR:%'
      ]
    );
    // later steps of the plan see the failure and stay out
    Assert.isFalse(PMS_DemoData.runStep(plan, 1));
    Assert.isFalse(PMS_DemoData.runStep(plan, 2));
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Demo_Record__c WHERE Object_Name__c != 'marker']
    );
  }

  @IsTest
  static void aSkippedStepMarksEveryPackOfThePlan() {
    admin('allow');
    insert new List<PMS_Demo_Record__c>{
      marker('baseline', 'START:'),
      marker('baseline', 'ERR:'),
      marker('overdue-wave', 'START:')
    };
    List<String> plan = new List<String>{
      'baseline:hotel',
      'overdue-wave:wave'
    };
    Assert.isFalse(PMS_DemoData.runStep(plan, 0));
    Assert.areEqual(PMS_DemoData.FAILED, pack('overdue-wave').state);
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Demo_Record__c
        WHERE Pack__c = 'baseline' AND Record_Id__c LIKE 'ERR:%'
      ],
      'the baseline marker is not duplicated'
    );
  }

  @IsTest
  static void aPackOnAFailedBaselineIsFailedEvenWithoutItsOwnMarker() {
    admin('allow');
    insert new List<PMS_Demo_Record__c>{
      marker('baseline', 'ERR:'),
      marker('overdue-wave', 'START:')
    };
    PMS_DemoData.PackInfo wave = pack('overdue-wave');
    Assert.areEqual(PMS_DemoData.FAILED, wave.state);
    Assert.isTrue(wave.message.contains('baseline'), wave.message);
  }

  // ------------------------------------------------------------------ S4 governor headroom of batched steps

  /**
   * A Developer Edition / trial org runs the 9 baseline steps in 5 chained jobs: 2, 2, 2, 2 and 1 steps. The
   * tests queue every step up front, so this runs the same pairs (a job each, with fresh limits) and checks how
   * much of each limit a job uses. If this fails, lower the batching in PMS_DemoData.stepsPerJob.
   */
  @IsTest
  static void batchedStepsStayWellInsideTheLimits() {
    admin('allow');
    List<String> plan = new List<String>();
    for (
      String step : new List<String>{
        'core',
        'hotel',
        'property',
        'projects',
        'practice',
        'billing',
        'service',
        'ops',
        'channels'
      }
    ) {
      plan.add('baseline:' + step);
    }
    // the batch sizes a depth 5 chain really gets
    List<Integer> sizes = new List<Integer>();
    Integer left = plan.size();
    for (Integer depth = 1; depth <= 5; depth++) {
      Integer n = PMS_DemoData.stepsPerJob(left, depth, 5);
      sizes.add(n);
      left -= n;
    }
    Assert.areEqual(0, left);
    Assert.areEqual(new List<Integer>{ 2, 2, 2, 2, 1 }, sizes);
    insert marker('baseline', 'START:');

    PMS_DemoData.perJobForTest = 2;
    PMS_DemoData.jobStats = new List<String>();
    Test.startTest();
    for (Integer start : new List<Integer>{ 0, 2, 4, 6, 8 }) {
      System.enqueueJob(new PMS_DemoData.StepJob(plan, start));
    }
    Test.stopTest();
    PMS_DemoData.perJobForTest = null;

    Assert.areEqual(
      PMS_DemoData.DONE,
      pack('baseline').state,
      'baseline: ' + pack('baseline').message
    );
    Assert.areEqual(
      5,
      PMS_DemoData.jobStats.size(),
      'one entry per job: ' + PMS_DemoData.jobStats
    );
    for (String s : PMS_DemoData.jobStats) {
      List<String> v = s.split('\\|');
      Assert.isTrue(Integer.valueOf(v[0]) < 80, 'SOQL queries ' + s);
      Assert.isTrue(Integer.valueOf(v[1]) < 8000, 'CPU ms ' + s);
      Assert.isTrue(Integer.valueOf(v[2]) < 8000, 'DML rows ' + s);
    }
    System.debug(
      LoggingLevel.INFO,
      'PMS demo data job usage (queries|cpu|dml rows|steps): ' +
      PMS_DemoData.jobStats
    );
  }

  // ------------------------------------------------------------------ S5 reset safety

  @IsTest
  static void resetDropsBadTrackingRowsAndNeverDeletesWhatIsNotDemoData() {
    admin('allow');
    Account demo = new Account(Name = 'Demo Co');
    Account stranger = new Account(Name = 'Not demo');
    insert new List<Account>{ demo, stranger };
    Id someUser = UserInfo.getUserId();
    insert new List<PMS_Demo_Record__c>{
      row('busy-weekend', demo.Id, 'Account', 1), // fine
      row('busy-weekend', stranger.Id, 'Contact', 1), // wrong object name for this Id
      row('busy-weekend', someUser, 'User', 1), // real Id, real name, but not a demo object
      new PMS_Demo_Record__c(
        Name = 'k.bad',
        Pack__c = 'busy-weekend',
        Record_Id__c = 'not-an-id',
        Object_Name__c = 'Account',
        Sequence__c = 1
      )
    };
    Assert.areEqual(
      'DONE',
      PMS_DemoData.resetPass(new List<String>{ 'busy-weekend' })
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Account WHERE Id = :demo.Id],
      'the demo account is gone'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Account WHERE Id = :stranger.Id],
      'mismatching rows never delete'
    );
    Assert.areEqual(1, [SELECT COUNT() FROM User WHERE Id = :someUser]);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Demo_Record__c],
      'bad rows are dropped'
    );
  }

  @IsTest
  static void isSafeToDeleteChecksIdObjectAndAllowList() {
    Account a = new Account(Name = 'x');
    insert a;
    Set<String> allowed = new Set<String>{ 'Account' };
    Assert.isTrue(
      PMS_DemoData.isSafeToDelete(row('p', a.Id, 'Account', 1), allowed)
    );
    Assert.isFalse(
      PMS_DemoData.isSafeToDelete(row('p', a.Id, 'Contact', 1), allowed)
    );
    Assert.isFalse(
      PMS_DemoData.isSafeToDelete(
        row('p', a.Id, 'Account', 1),
        new Set<String>()
      )
    );
    PMS_Demo_Record__c bad = row('p', a.Id, 'Account', 1);
    bad.Record_Id__c = '';
    Assert.isFalse(PMS_DemoData.isSafeToDelete(bad, allowed));
    bad.Record_Id__c = 'zzzzzzzzzzzzzzz';
    Assert.isFalse(PMS_DemoData.isSafeToDelete(bad, allowed));
  }

  @IsTest
  static void accountsWithRecordsOfTheirOwnAreKept() {
    admin('allow');
    Account busy = new Account(Name = 'Demo with a stranger');
    Account clean = new Account(Name = 'Demo clean');
    insert new List<Account>{ busy, clean };
    Contact mine = new Contact(LastName = 'Demo', AccountId = busy.Id);
    Contact theirs = new Contact(
      LastName = 'Real customer',
      AccountId = busy.Id
    );
    insert new List<Contact>{ mine, theirs };
    insert new List<PMS_Demo_Record__c>{
      row('busy-weekend', busy.Id, 'Account', 1),
      row('busy-weekend', clean.Id, 'Account', 1),
      row('busy-weekend', mine.Id, 'Contact', 2)
    };
    PMS_DemoData.keptReport = new List<String>();
    Assert.areEqual(
      'DONE',
      PMS_DemoData.resetPass(new List<String>{ 'busy-weekend' })
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Account WHERE Id = :busy.Id],
      'kept'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Account WHERE Id = :clean.Id],
      'removed'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Contact WHERE Id = :theirs.Id],
      'the real customer survives'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Contact WHERE Id = :mine.Id],
      'the demo contact is removed'
    );
    Assert.areEqual(
      1,
      PMS_DemoData.keptReport.size(),
      String.join(PMS_DemoData.keptReport, ',')
    );
    Assert.isTrue(PMS_DemoData.keptReport[0].contains(busy.Id));
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Demo_Record__c],
      'it is no longer tracked'
    );
  }

  @IsTest
  static void sitesWithSpacesOfTheirOwnAreKept() {
    admin('allow');
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    insert new List<PMS_Demo_Record__c>{
      row('busy-weekend', p.site.Id, 'PMS_Site__c', 1)
    };
    PMS_DemoData.keptReport = new List<String>();
    Assert.areEqual(
      'DONE',
      PMS_DemoData.resetPass(new List<String>{ 'busy-weekend' })
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Site__c WHERE Id = :p.site.Id],
      'the site has a space nobody tracked'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Space__c WHERE Id = :p.unit.Id]
    );
    Assert.areEqual(1, PMS_DemoData.keptReport.size());
  }

  // ------------------------------------------------------------------ S2 side effects on demo records

  @IsTest
  static void demoInvoicesAreExcludedFromRealDunning() {
    admin('allow');
    Test.startTest();
    PMS_DemoData.load('overdue-wave');
    Test.stopTest();
    Assert.isTrue([SELECT COUNT() FROM PMS_Invoice__c] > 12);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Invoice__c WHERE Dunning_Paused__c = FALSE],
      'every demo invoice is paused'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PMS_Invoice__c
        WHERE Dunning_Pause_Reason__c != 'Demo data'
      ]
    );
    Assert.isTrue(
      [SELECT COUNT() FROM PMS_Dunning_Event__c] > 0,
      'the hand-made reminder history is kept'
    );
  }

  @IsTest
  static void demoBookingsAreMarkedAsAlreadyMailed() {
    admin('allow');
    Test.startTest();
    PMS_DemoData.load('baseline');
    Test.stopTest();
    Assert.isTrue([SELECT COUNT() FROM PMS_Booking__c] > 20);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Booking__c WHERE Card_Link_Sent_At__c = NULL],
      'the guarantee job never mails demo guests'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Booking__c WHERE Check_In_Invited_At__c = NULL],
      'the check-in invitation job never mails demo guests'
    );
  }
}
