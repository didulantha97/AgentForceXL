@isTest
private class PMS_DynamicPricingTest {
  @TestSetup
  static void setup() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(4); // Double, default rate 1000; BAR plan has 1200 / 1500 Fri-Sat
    PMS_Pricing_Strategy__c s = new PMS_Pricing_Strategy__c(
      Name = 'BAR dynamic',
      Rate_Plan__c = h.plan.Id,
      Active__c = true,
      Horizon_Days__c = 14,
      Min_Percent__c = 80,
      Max_Percent__c = 150,
      Round_To__c = 10
    );
    insert s;
    insert new List<PMS_Pricing_Factor__c>{
      new PMS_Pricing_Factor__c(
        Name = 'Busy',
        Strategy__c = s.Id,
        Active__c = true,
        Type__c = 'Occupancy',
        Min_Value__c = 50,
        Adjust_Percent__c = 20
      ),
      new PMS_Pricing_Factor__c(
        Name = 'Last minute',
        Strategy__c = s.Id,
        Active__c = true,
        Type__c = 'Lead Time',
        Min_Value__c = 0,
        Max_Value__c = 2,
        Adjust_Percent__c = -10
      ),
      new PMS_Pricing_Factor__c(
        Name = 'Concert',
        Strategy__c = s.Id,
        Active__c = true,
        Type__c = 'Event',
        Date_From__c = Date.today().addDays(5),
        Date_To__c = Date.today().addDays(6),
        Adjust_Amount__c = 300
      )
    };
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'PMS_Dynamic_Pricing'
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

  private static PMS_Pricing_Strategy__c strategy() {
    return [SELECT Id, Rate_Plan__c FROM PMS_Pricing_Strategy__c LIMIT 1];
  }

  @isTest
  static void formulaAndGuardrails() {
    PMS_Pricing_Strategy__c s = new PMS_Pricing_Strategy__c(
      Min_Percent__c = 80,
      Max_Percent__c = 150,
      Round_To__c = 10,
      Max_Change_Percent__c = 10
    );
    List<PMS_Pricing_Factor__c> factors = new List<PMS_Pricing_Factor__c>{
      new PMS_Pricing_Factor__c(
        Name = 'Weekend',
        Active__c = true,
        Type__c = 'Day of Week',
        Days_Of_Week__c = 'Friday;Saturday',
        Adjust_Percent__c = 25
      ),
      new PMS_Pricing_Factor__c(
        Name = 'Very busy',
        Active__c = true,
        Type__c = 'Occupancy',
        Min_Value__c = 90,
        Adjust_Percent__c = 100
      )
    };
    Date friday = Date.today();
    while (PMS_DynamicPricingService.dayName(friday) != 'Friday') {
      friday = friday.addDays(1);
    }
    Assert.areEqual('Friday', PMS_DynamicPricingService.dayName(friday));
    List<String> notes = new List<String>();
    PMS_TestDataFactory.num(
      1250,
      PMS_DynamicPricingService.price(
        s,
        factors,
        null,
        friday,
        1000,
        10,
        5,
        null,
        notes
      ),
      'weekend +25%'
    );
    Assert.isTrue(notes[0].startsWith('Weekend'), String.join(notes, ','));
    PMS_TestDataFactory.num(
      1500,
      PMS_DynamicPricingService.price(
        s,
        factors,
        null,
        friday,
        1000,
        95,
        5,
        null,
        new List<String>()
      ),
      'ceiling 150%'
    );
    PMS_TestDataFactory.num(
      1100,
      PMS_DynamicPricingService.price(
        s,
        factors,
        null,
        friday,
        1000,
        95,
        5,
        1000,
        new List<String>()
      ),
      'max change 10%'
    );
    s.Min_Rate__c = 900;
    factors.add(
      new PMS_Pricing_Factor__c(
        Name = 'Dead',
        Active__c = true,
        Type__c = 'Lead Time',
        Min_Value__c = 0,
        Max_Value__c = 1,
        Adjust_Percent__c = -50
      )
    );
    PMS_TestDataFactory.num(
      900,
      PMS_DynamicPricingService.price(
        s,
        factors,
        null,
        friday.addDays(3),
        1000,
        0,
        0,
        null,
        new List<String>()
      ),
      'floor amount beats 80%'
    );
    PMS_TestDataFactory.num(
      1010,
      PMS_DynamicPricingService.price(
        new PMS_Pricing_Strategy__c(Round_To__c = 10),
        new List<PMS_Pricing_Factor__c>(),
        null,
        friday,
        1006,
        null,
        5,
        null,
        new List<String>()
      ),
      'rounding'
    );
  }

  @isTest
  static void recalculateWritesDailyRatesThatQuotesUse() {
    PMS_Pricing_Strategy__c s = strategy();
    Test.startTest();
    PMS_DynamicPricingService.RunResult r = PMS_DynamicPricingService.recalculate(
      s.Id
    );
    Test.stopTest();
    PMS_Space_Type__c t = [SELECT Id FROM PMS_Space_Type__c LIMIT 1];
    Assert.areEqual(14, r.written, r.summary);
    Assert.areEqual(
      14,
      [SELECT COUNT() FROM PMS_Rate__c WHERE Dynamic__c = TRUE]
    );

    Date night = Date.today().addDays(5); // event night, 5 days ahead, nothing sold
    PMS_Rate__c rate = [
      SELECT Amount__c, Base_Amount__c, Pricing_Notes__c
      FROM PMS_Rate__c
      WHERE Dynamic__c = TRUE AND Date_From__c = :night
    ];
    Decimal base = rate.Base_Amount__c;
    Assert.isTrue(
      base == 1200 || base == 1500,
      'base from the plan rates: ' + base
    );
    PMS_TestDataFactory.num(
      Math.min(base + 300, base * 1.5),
      rate.Amount__c,
      'event +300 within ceiling'
    );
    Assert.isTrue(
      rate.Pricing_Notes__c.contains('Concert'),
      rate.Pricing_Notes__c
    );

    // The ordinary quote engine now uses the daily rate.
    PMS_PricingService.QuoteRequest q = new PMS_PricingService.QuoteRequest();
    q.module = 'Hotel';
    q.ratePlanId = s.Rate_Plan__c;
    q.spaceTypeId = t.Id;
    q.startDate = night;
    q.endDate = night.addDays(1);
    PMS_PricingService.Quote quote = PMS_PricingService.quote(q);
    PMS_TestDataFactory.num(
      rate.Amount__c,
      quote.net,
      'quote uses the dynamic rate'
    );

    PMS_Rate__c tonight = [
      SELECT Amount__c, Base_Amount__c, Pricing_Notes__c
      FROM PMS_Rate__c
      WHERE Dynamic__c = TRUE AND Date_From__c = :Date.today()
    ];
    Assert.isTrue(
      tonight.Pricing_Notes__c.contains('Last minute'),
      tonight.Pricing_Notes__c
    );
    Assert.isTrue(
      tonight.Amount__c < tonight.Base_Amount__c,
      'last minute is cheaper'
    );
  }

  @isTest
  static void lockedRatesSurviveRecalculation() {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PMS_Pricing_Strategy__c s = strategy();
      PMS_DynamicPricingService.recalculate(s.Id);
      PMS_Rate__c r = [
        SELECT Id
        FROM PMS_Rate__c
        WHERE Dynamic__c = TRUE AND Date_From__c = :Date.today().addDays(3)
      ];
      PMS_PricingCalendarController.setPrice(r.Id, 2222);
      PMS_DynamicPricingService.RunResult again = PMS_PricingCalendarController.recalculate(
        s.Rate_Plan__c
      );
      Assert.areEqual(1, again.locked);
      PMS_Rate__c after = [
        SELECT Amount__c, Locked__c
        FROM PMS_Rate__c
        WHERE Id = :r.Id
      ];
      PMS_TestDataFactory.num(2222, after.Amount__c, 'kept');
      Assert.isTrue(after.Locked__c);
      PMS_PricingCalendarController.unlock(r.Id);
      PMS_PricingCalendarController.recalculate(s.Id);
      Assert.areNotEqual(
        2222,
        [SELECT Amount__c FROM PMS_Rate__c WHERE Id = :r.Id].Amount__c,
        'recalculated after unlock'
      );
      Assert.areEqual(
        14,
        [SELECT COUNT() FROM PMS_Rate__c WHERE Dynamic__c = TRUE],
        'no duplicates'
      );
    }
  }

  @isTest
  static void occupancyRaisesRates() {
    PMS_Pricing_Strategy__c s = strategy();
    PMS_Space_Type__c t = [SELECT Id FROM PMS_Space_Type__c LIMIT 1];
    Date night = Date.today().addDays(4);
    insert new PMS_Inventory_Day__c(
      Room_Type__c = t.Id,
      Inventory_Date__c = night,
      Total_Rooms__c = 4,
      Sold__c = 3,
      Out_Of_Order__c = 0
    );
    PMS_DynamicPricingService.recalculate(s.Id);
    PMS_Rate__c r = [
      SELECT Amount__c, Base_Amount__c, Occupancy__c, Pricing_Notes__c
      FROM PMS_Rate__c
      WHERE Dynamic__c = TRUE AND Date_From__c = :night
    ];
    PMS_TestDataFactory.num(75, r.Occupancy__c, 'occupancy from inventory');
    Assert.isTrue(r.Pricing_Notes__c.contains('Busy'), r.Pricing_Notes__c);
    Assert.isTrue(r.Amount__c > r.Base_Amount__c);
  }

  @isTest
  static void emptyJobRunnerIsIgnored() {
    new PMS_DynamicPricingJob.Runner(new List<Id>()).execute(null);
  }

  @isTest
  static void jobRunnerRecordsFailures() {
    PMS_Pricing_Strategy__c invalid = new PMS_Pricing_Strategy__c(
      Name = 'Missing rate plan',
      Active__c = true
    );
    insert invalid;

    new PMS_DynamicPricingJob.Runner(new List<Id>{ invalid.Id }).execute(null);

    invalid = [
      SELECT Last_Run_At__c, Last_Run_Result__c
      FROM PMS_Pricing_Strategy__c
      WHERE Id = :invalid.Id
    ];
    Assert.isNotNull(invalid.Last_Run_At__c);
    Assert.isTrue(invalid.Last_Run_Result__c.startsWith('Failed:'));
  }

  @isTest
  static void calendarAndJob() {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PMS_Pricing_Strategy__c s = strategy();
      PMS_DynamicPricingService.recalculate(s.Id);
      PMS_PricingCalendarController.Calendar c = PMS_PricingCalendarController.getCalendar(
        s.Rate_Plan__c,
        14
      );
      Assert.areEqual(1, c.roomTypes.size());
      Assert.areEqual(14, c.nights.size());
      Assert.isNotNull(c.nights[0].cells[0].rateId);
      try {
        PMS_PricingCalendarController.setPrice(c.nights[0].cells[0].rateId, 0);
        Assert.fail('zero is not a rate');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('positive'), e.getMessage());
      }
      Test.startTest();
      String jobId = System.schedule(
        'PMS Dynamic Pricing test',
        '0 25 * * * ?',
        new PMS_DynamicPricingJob()
      );
      System.enqueueJob(new PMS_DynamicPricingJob.Runner(new List<Id>{ s.Id }));
      Test.stopTest();
      Assert.isNotNull(jobId);
      Assert.isNotNull(
        [SELECT Last_Run_At__c FROM PMS_Pricing_Strategy__c WHERE Id = :s.Id]
        .Last_Run_At__c
      );
    }
  }
}
