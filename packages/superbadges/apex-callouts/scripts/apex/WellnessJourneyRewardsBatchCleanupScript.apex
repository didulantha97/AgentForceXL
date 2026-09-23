// Removes the test data created by WellnessJourneyRewardsBatchScript.apex.
// Matches records by the 'Badge Test ' name prefix used when generating them,
// so this only ever deletes records created by that script (not real journeys).
List<Wellness_Journey__c> journeysToDelete = [
    SELECT Id, Name
    FROM Wellness_Journey__c
    WHERE Name LIKE 'Badge Test %'
];

System.debug('Deleting ' + journeysToDelete.size() + ' Wellness_Journey__c test record(s).');

if (!journeysToDelete.isEmpty()) {
    delete journeysToDelete;
}
