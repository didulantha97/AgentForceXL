// Removes the test data created by WorkshopTriggerScript.apex.
// That script inserts a Workshop__c named 'My Workshop2', and because
// DHH_Accessible__c is true, WorkshopTrigger also inserts an
// Accessibility_Project__c (Type__c = 'Sign Language Interpreters',
// Status__c = 'Submitted'). There's no lookup between the two objects, so
// the Accessibility_Project__c records are matched by the same CreatedDate
// as the Workshop__c they were created alongside (same trigger transaction).
List<Workshop__c> workshopsToDelete = [
    SELECT Id, CreatedDate
    FROM Workshop__c
    WHERE Name = 'My Workshop'
];

Set<Datetime> createdDates = new Set<Datetime>();
for (Workshop__c w : workshopsToDelete) {
    createdDates.add(w.CreatedDate);
}

List<Accessibility_Project__c> projectsToDelete = createdDates.isEmpty()
    ? new List<Accessibility_Project__c>()
    : [
        SELECT Id
        FROM Accessibility_Project__c
        WHERE Type__c = 'Sign Language Interpreters'
        AND Status__c = 'Submitted'
        AND CreatedDate IN :createdDates
    ];

System.debug('Deleting ' + projectsToDelete.size() + ' Accessibility_Project__c test record(s).');
if (!projectsToDelete.isEmpty()) {
    delete projectsToDelete;
}

System.debug('Deleting ' + workshopsToDelete.size() + ' Workshop__c test record(s).');
if (!workshopsToDelete.isEmpty()) {
    delete workshopsToDelete;
}
