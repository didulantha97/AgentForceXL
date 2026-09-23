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
