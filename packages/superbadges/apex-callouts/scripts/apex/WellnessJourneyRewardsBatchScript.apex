// Prepare enough qualifying data to exercise WellnessJourneyRewardsBatch.
// The batch rewards an owner after 12 completed journeys in the previous quarter.
Date today = Date.today();
Integer currentQuarterStartMonth = ((today.month() - 1) / 3) * 3 + 1;
Date currentQuarterStart = Date.newInstance(
    today.year(),
    currentQuarterStartMonth,
    1
);
Date previousQuarterStart = currentQuarterStart.addMonths(-3);

// Give every execution its own identifier so the generated test records are
// easy to distinguish from records created by earlier executions.
String runKey = String.valueOf(Datetime.now().getTime()) + '-' +
    EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);

List<Wellness_Journey__c> journeys = new List<Wellness_Journey__c>();
for (Integer i = 1; i <= 12; i++) {
    journeys.add(new Wellness_Journey__c(
        Name = 'Badge Test ' + runKey + '-' + i,
        Description__c = 'Rewards batch test run ' + runKey + '.',
        Status__c = 'Complete',
        Completion_Date__c = Datetime.newInstance(
            previousQuarterStart.addDays(i),
            Time.newInstance(12, 0, 0, 0)
        )
    ));
}
insert journeys;

// Batch classes are started through Database.executeBatch, not by calling
// execute directly. Keep all 12 records in the same batch scope.
Id batchJobId = Database.executeBatch(new WellnessJourneyRewardsBatch(), 200);
System.debug('WellnessJourneyRewardsBatch job ID: ' + batchJobId);
