@isTest
private class RewardsCalloutServiceTest {

    private static final String TEST_OWNER_LAST_NAME = 'RewardsTestOwner';

    // Wellness_Journey__c.Owner is a pre-existing running user, not a record inserted by this
    // test. Apex test data isolation hides relationship fields (Owner.Name/Email/Username) for
    // records outside the test transaction, so a dedicated user is created in @testSetup -
    // records created there are visible to relationship queries in every test method.
    @testSetup
    static void setupTestOwner() {
        Profile standardUserProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        insert new User(
            FirstName = 'Rewards',
            LastName = TEST_OWNER_LAST_NAME,
            Alias = 'rwtowr',
            Email = 'rewards.test.owner@rewardstest.invalid',
            Username = 'rewards.test.owner.' + UserInfo.getOrganizationId() + '@rewardstest.invalid',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardUserProfile.Id
        );
    }

    private static User getTestOwner() {
        return [SELECT Id, Name, Email, Username FROM User WHERE LastName = :TEST_OWNER_LAST_NAME LIMIT 1];
    }

    // Mirrors the private quarter-window logic in WellnessJourneyRewardsBatch so test data
    // always lines up with whatever quarter "today" falls into when the tests run.
    private static Date getStartDateCopy() {
        Date today = Date.today();

        Integer currentYear = today.year();
        Integer currentMonth = today.month();

        Integer previousQuarterStartMonth = ((currentMonth - 1) / 3) * 3 + 1 - 3;

        if (previousQuarterStartMonth <= 0) {
            previousQuarterStartMonth += 12;
            currentYear--;
        }

        return Date.newInstance(currentYear, previousQuarterStartMonth, 1);
    }

    private static Date getEndDateCopy() {
        Date startDateCopy = getStartDateCopy();
        return startDateCopy.addMonths(3).addDays(-1);
    }

    private static void logQuarterWindow(String context) {
        System.debug(LoggingLevel.INFO, context + ' -> startDateCopy=' + getStartDateCopy() + ', endDateCopy=' + getEndDateCopy());
    }

    // Builds journeys on interior days of the quarter (never on the first/last day) so the
    // records are unambiguously inside the SOQL date range regardless of Date/DateTime
    // boundary conversion rules for the >= / <= comparison in the batch query.
    private static List<Wellness_Journey__c> buildJourneysForTestOwner(Integer count, String status, Id ownerId) {
        Date startDateCopy = getStartDateCopy();
        List<Wellness_Journey__c> journeys = new List<Wellness_Journey__c>();

        for (Integer i = 0; i < count; i++) {
            Datetime completionDateTime = Datetime.newInstance(startDateCopy.addDays(5 + Math.mod(i, 75)), Time.newInstance(10, 0, 0, 0));

            journeys.add(new Wellness_Journey__c(
                Name = 'Test Journey ' + i,
                Status__c = status,
                Completion_Date__c = completionDateTime,
                OwnerId = ownerId
            ));
        }

        return journeys;
    }

    // Wraps RewardsCalloutServiceMock so tests can assert on the actual request the batch
    // sent, while still exercising the same response logic used in production tests.
    private class CapturingCalloutMock implements HttpCalloutMock {
        public HttpRequest lastRequest;

        public HttpResponse respond(HttpRequest request) {
            lastRequest = request;
            return new RewardsCalloutServiceMock().respond(request);
        }
    }

    // Simulates an API outage (connection failure) rather than an HTTP error response.
    private class CalloutOutageMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('System.CalloutException: Unable to connect to the endpoint');
        }
    }

    // ---------------------------------------------------------------------
    // Quarter window calculation
    // ---------------------------------------------------------------------

    @isTest
    static void testStartDateCopyAndEndDateCopy_MatchPreviousQuarterWindow() {
        Date startDateCopy = getStartDateCopy();
        Date endDateCopy = getEndDateCopy();

        logQuarterWindow('testStartDateCopyAndEndDateCopy_MatchPreviousQuarterWindow');

        Assert.areEqual(1, startDateCopy.day(), 'Quarter should start on the 1st of the month');
        Assert.isTrue(
            new Set<Integer>{ 1, 4, 7, 10 }.contains(startDateCopy.month()),
            'Quarter start month should be Jan, Apr, Jul or Oct'
        );
        Assert.areEqual(startDateCopy.addMonths(3).addDays(-1), endDateCopy, 'End date should be the last day of a 3 month window');
        Assert.isTrue(endDateCopy < Date.today(), 'The computed quarter should be in the past relative to today');
    }

    // ---------------------------------------------------------------------
    // RewardsCalloutServiceMock response accuracy
    // ---------------------------------------------------------------------

    @isTest
    static void testMock_RewardsEndpoint_ReturnsSuccessResponse() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:IntegrationSB__BalancedLiving/rewards');
        req.setMethod('POST');

        Test.startTest();
        HttpResponse res = new RewardsCalloutServiceMock().respond(req);
        Test.stopTest();

        Assert.areEqual(201, res.getStatusCode(), 'Rewards endpoint should mimic a successful creation response');
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Assert.areEqual('Success', body.get('message'));
    }

    @isTest
    static void testMock_JourneyCompletionEndpoint_ReturnsPoints() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:IntegrationSB__BalancedLiving/journey/completion');
        req.setMethod('POST');

        Test.startTest();
        HttpResponse res = new RewardsCalloutServiceMock().respond(req);
        Test.stopTest();

        Assert.areEqual(200, res.getStatusCode());
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Assert.areEqual(500, (Integer) body.get('points'));
    }

    @isTest
    static void testMock_EngagementRateEndpoint_ReturnsStatus() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:IntegrationSB__BalancedLiving/engagement-rate');
        req.setMethod('GET');

        Test.startTest();
        HttpResponse res = new RewardsCalloutServiceMock().respond(req);
        Test.stopTest();

        Assert.areEqual(200, res.getStatusCode());
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Assert.areEqual('Great', body.get('status'));
    }

    @isTest
    static void testMock_JourneysEndpoint_ReturnsJourneyList() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:IntegrationSB__BalancedLiving/journeys/123');
        req.setMethod('GET');

        Test.startTest();
        HttpResponse res = new RewardsCalloutServiceMock().respond(req);
        Test.stopTest();

        Assert.areEqual(200, res.getStatusCode());
        List<Object> body = (List<Object>) JSON.deserializeUntyped(res.getBody());
        Assert.areEqual(1, body.size());
    }

    @isTest
    static void testMock_UnknownEndpoint_Returns404() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:IntegrationSB__BalancedLiving/unknown-path');
        req.setMethod('GET');

        Test.startTest();
        HttpResponse res = new RewardsCalloutServiceMock().respond(req);
        Test.stopTest();

        Assert.areEqual(404, res.getStatusCode());
    }

    @isTest
    static void testMock_ForcedBadRequest_OverridesEndpointRouting() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:IntegrationSB__BalancedLiving/rewards');
        req.setMethod('POST');

        RewardsCalloutServiceMock.statusCode = 400;

        Test.startTest();
        HttpResponse res = new RewardsCalloutServiceMock().respond(req);
        Test.stopTest();

        RewardsCalloutServiceMock.statusCode = 200;

        Assert.areEqual(400, res.getStatusCode());
    }

    @isTest
    static void testMock_ForcedServerError_OverridesEndpointRouting() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:IntegrationSB__BalancedLiving/rewards');
        req.setMethod('POST');

        RewardsCalloutServiceMock.statusCode = 500;

        Test.startTest();
        HttpResponse res = new RewardsCalloutServiceMock().respond(req);
        Test.stopTest();

        RewardsCalloutServiceMock.statusCode = 200;

        Assert.areEqual(500, res.getStatusCode());
    }

    // ---------------------------------------------------------------------
    // RewardsCalloutService.submitUsersForRewardCallout
    // ---------------------------------------------------------------------

    @isTest
    static void testSubmitUsersForRewardCallout_SuccessReturns201() {
        Test.setMock(HttpCalloutMock.class, new RewardsCalloutServiceMock());
        RewardsCalloutServiceMock.statusCode = 200;

        Test.startTest();
        Integer statusCode = RewardsCalloutService.submitUsersForRewardCallout(JSON.serialize(new List<Object>()));
        Test.stopTest();

        Assert.areEqual(201, statusCode, 'A healthy submission should surface the mocked 201 response code');
    }

    @isTest
    static void testSubmitUsersForRewardCallout_BadRequestReturns400() {
        Test.setMock(HttpCalloutMock.class, new RewardsCalloutServiceMock());
        RewardsCalloutServiceMock.statusCode = 400;

        Test.startTest();
        Integer statusCode = RewardsCalloutService.submitUsersForRewardCallout(JSON.serialize(new List<Object>()));
        Test.stopTest();

        RewardsCalloutServiceMock.statusCode = 200;

        Assert.areEqual(400, statusCode, 'Malformed payloads should surface the mocked 400 response code');
    }

    @isTest
    static void testSubmitUsersForRewardCallout_ServerErrorReturns500() {
        Test.setMock(HttpCalloutMock.class, new RewardsCalloutServiceMock());
        RewardsCalloutServiceMock.statusCode = 500;

        Test.startTest();
        Integer statusCode = RewardsCalloutService.submitUsersForRewardCallout(JSON.serialize(new List<Object>()));
        Test.stopTest();

        RewardsCalloutServiceMock.statusCode = 200;

        Assert.areEqual(500, statusCode, 'An outage response from the external service should surface the mocked 500 response code');
    }

    // ---------------------------------------------------------------------
    // WellnessJourneyRewardsBatch end-to-end scenarios
    // ---------------------------------------------------------------------

    @isTest
    static void testBatch_SubmitsOnlyUsersWithTwelveOrMoreCompletedJourneys() {
        User testOwner = getTestOwner();
        insert buildJourneysForTestOwner(12, 'Complete', testOwner.Id);
        logQuarterWindow('testBatch_SubmitsOnlyUsersWithTwelveOrMoreCompletedJourneys');

        CapturingCalloutMock mock = new CapturingCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Id jobId = Database.executeBatch(new WellnessJourneyRewardsBatch());
        Test.stopTest();

        Assert.isNotNull(mock.lastRequest, 'The batch should have made a callout');
        List<Object> submittedUsers = (List<Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        Assert.areEqual(1, submittedUsers.size(), 'Exactly one qualifying user should be submitted');

        Map<String, Object> userPayload = (Map<String, Object>) submittedUsers[0];
        Assert.areEqual(String.valueOf(testOwner.Id), (String) userPayload.get('userId'));
        Assert.areEqual(testOwner.Name, (String) userPayload.get('fullName'));
        Assert.areEqual(testOwner.Email, (String) userPayload.get('email'));
        Assert.areEqual(testOwner.Username, (String) userPayload.get('username'));

        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        Assert.areEqual('Completed', job.Status);
        Assert.areEqual(0, job.NumberOfErrors);
    }

    @isTest
    static void testBatch_ExcludesUsersWithFewerThanTwelveCompletedJourneys() {
        User testOwner = getTestOwner();
        insert buildJourneysForTestOwner(11, 'Complete', testOwner.Id);

        CapturingCalloutMock mock = new CapturingCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new WellnessJourneyRewardsBatch());
        Test.stopTest();

        Assert.isNotNull(mock.lastRequest, 'The batch should still run a callout with an empty payload');
        List<Object> submittedUsers = (List<Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        Assert.areEqual(0, submittedUsers.size(), 'A user under the 12-journey threshold should not be submitted');
    }

    @isTest
    static void testBatch_ExcludesJourneysOutsideTheQuarterWindow() {
        User testOwner = getTestOwner();
        Date startDateCopy = getStartDateCopy();
        List<Wellness_Journey__c> journeys = new List<Wellness_Journey__c>();
        for (Integer i = 0; i < 12; i++) {
            journeys.add(new Wellness_Journey__c(
                Name = 'Out Of Window Journey ' + i,
                Status__c = 'Complete',
                Completion_Date__c = Datetime.newInstance(startDateCopy.addDays(-30), Time.newInstance(10, 0, 0, 0)),
                OwnerId = testOwner.Id
            ));
        }
        insert journeys;

        CapturingCalloutMock mock = new CapturingCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new WellnessJourneyRewardsBatch());
        Test.stopTest();

        // A query locator with zero matching rows never invokes execute(), so no callout
        // is made at all - not even one with an empty payload.
        Assert.isNull(mock.lastRequest, 'Journeys completed outside the target quarter should never reach the batch scope, so no callout should be made');
    }

    @isTest
    static void testBatch_ExcludesJourneysNotMarkedComplete() {
        User testOwner = getTestOwner();
        insert buildJourneysForTestOwner(12, 'In Progress', testOwner.Id);

        CapturingCalloutMock mock = new CapturingCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new WellnessJourneyRewardsBatch());
        Test.stopTest();

        Assert.isNull(mock.lastRequest, 'Journeys that are not Complete should never reach the batch scope, so no callout should be made');
    }

    @isTest
    static void testBatch_BadResponseFromServiceDoesNotFailTheJob() {
        User testOwner = getTestOwner();
        insert buildJourneysForTestOwner(12, 'Complete', testOwner.Id);

        Test.setMock(HttpCalloutMock.class, new RewardsCalloutServiceMock());
        RewardsCalloutServiceMock.statusCode = 400;

        Test.startTest();
        Id jobId = Database.executeBatch(new WellnessJourneyRewardsBatch());
        Test.stopTest();

        RewardsCalloutServiceMock.statusCode = 200;

        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        Assert.areEqual('Completed', job.Status, 'A 400 response is only logged today, so the batch job itself should still complete');
        Assert.areEqual(0, job.NumberOfErrors);
    }

    @isTest
    static void testBatch_ApiOutageSurfacesAsBatchExecutionError() {
        User testOwner = getTestOwner();
        insert buildJourneysForTestOwner(12, 'Complete', testOwner.Id);

        Test.setMock(HttpCalloutMock.class, new CalloutOutageMock());

        // WellnessJourneyRewardsBatch has no try/catch around the callout, so when Test.stopTest()
        // drives the batch synchronously, an outage surfaces as an exception out of stopTest()
        // itself rather than being recorded silently on the AsyncApexJob.
        Boolean outagePropagated = false;
        Test.startTest();
        Database.executeBatch(new WellnessJourneyRewardsBatch());
        try {
            Test.stopTest();
        } catch (CalloutException ex) {
            outagePropagated = true;
            System.debug(LoggingLevel.INFO, 'testBatch_ApiOutageSurfacesAsBatchExecutionError -> caught: ' + ex.getMessage());
        }

        Assert.isTrue(outagePropagated, 'An API outage during the callout should surface as an unhandled CalloutException');
    }
}