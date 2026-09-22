// execute Trigger WorkshopTrigger using an anonymous block
// Add a new Workshop__c record to the database to trigger the logic in the trigger
// All fields on the Workshop__c object are required, so you must set a value for each field when creating the record. The only required field is Name, so you can set a value for that field and leave the other fields blank.
Workshop__c w = new Workshop__c();
w.Name = 'My Workshop2';
w.Description__c = 'This is a description of my workshop2.';
w.Capacity__c = 10;
w.Date__c = Date.today();
w.DHH_Accessible__c = true;
w.Facilitator__c = 'John Doe';
insert w;

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

List<Wellness_Journey__c> journeys = new List<Wellness_Journey__c>();
for (Integer i = 1; i <= 12; i++) {
    journeys.add(new Wellness_Journey__c(
        Name = 'Badge Test Journey ' + i,
        Description__c = 'Completed journey created to test the rewards batch.',
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
