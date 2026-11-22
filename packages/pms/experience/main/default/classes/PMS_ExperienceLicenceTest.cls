@isTest
private class PMS_ExperienceLicenceTest {
  private static PMS_Document_Request__c newDoc(Id accountId, Id contactId) {
    return new PMS_Document_Request__c(
      Title__c = 'Lease agreement',
      Account__c = accountId,
      Contact__c = contactId,
      Requires_Signature__c = false,
      Status__c = 'Draft'
    );
  }

  @isTest
  static void checkInJobSkipsAndLogsWhenSuspended() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    Test.startTest();
    new PMS_CheckInInvitationJob().execute(null);
    Test.stopTest();
    PMS_Entitlements.forceStateForTest(null);
    Assert.isTrue(
      String.valueOf(PMS_License__c.getOrgDefaults().Last_Error__c)
        .contains('PMS_CheckInInvitationJob'),
      'the skipped run is logged'
    );
  }

  @isTest
  static void checkInJobCanBeScheduledAndRuns() {
    Test.startTest();
    Id jobId = PMS_CheckInInvitationJob.scheduleDaily();
    new PMS_CheckInInvitationJob().execute(null);
    Test.stopTest();
    Assert.areEqual(
      PMS_CheckInInvitationJob.JOB_NAME,
      [SELECT CronJobDetail.Name FROM CronTrigger WHERE Id = :jobId]
      .CronJobDetail.Name
    );
  }

  @isTest
  static void documentRequestWritesAreBlockedWhenSuspended() {
    Account a = PMS_ExperienceTestFactory.account('Doc AB');
    Contact c = PMS_ExperienceTestFactory.contact(a.Id, 'Doc');
    PMS_Document_Request__c d = newDoc(a.Id, c.Id);
    insert d;
    delete d;

    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    Assert.isFalse(
      Database.undelete(d.Id, false).isSuccess(),
      'restore is a locked write'
    );
    Assert.isFalse(
      Database.insert(newDoc(a.Id, c.Id), false).isSuccess(),
      'insert is a locked write'
    );
    PMS_Entitlements.forceStateForTest(null);

    undelete d;
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    d.Title__c = 'Changed';
    Assert.isFalse(
      Database.update(d, false).isSuccess(),
      'update is a locked write'
    );
    PMS_Entitlements.forceStateForTest(null);
    Assert.areEqual(
      'Lease agreement',
      [SELECT Title__c FROM PMS_Document_Request__c WHERE Id = :d.Id].Title__c
    );
  }

  @isTest
  static void documentRequestBulkInsertAndUndeleteWhenLicensed() {
    Account a = PMS_ExperienceTestFactory.account('Bulk AB');
    Contact c = PMS_ExperienceTestFactory.contact(a.Id, 'Bulk');
    List<PMS_Document_Request__c> docs = new List<PMS_Document_Request__c>();
    for (Integer i = 0; i < 200; i++) {
      docs.add(newDoc(a.Id, c.Id));
    }
    Test.startTest();
    insert docs;
    delete docs;
    undelete docs;
    Test.stopTest();
    Assert.areEqual(200, [SELECT COUNT() FROM PMS_Document_Request__c]);
  }
}
