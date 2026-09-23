@IsTest
global class BillingCalloutServiceMock implements WebServiceMock {
    private String responseStatus;
    private Boolean shouldThrowError;

    global BillingCalloutServiceMock() {
        this('ok', false);
    }

    global BillingCalloutServiceMock(String responseStatus) {
        this(responseStatus, false);
    }

    global BillingCalloutServiceMock(String responseStatus, Boolean shouldThrowError) {
        this.responseStatus = responseStatus;
        this.shouldThrowError = shouldThrowError;
    }

    global void doInvoke(
        Object stub,
        Object request,
        Map<String, Object> response,
        String endpoint,
        String soapAction,
        String requestName,
        String responseNamespace,
        String responseName,
        String responseType
    ) {
        BillingServiceProxy.billProjectRequest_element billingRequest =
            (BillingServiceProxy.billProjectRequest_element) request;

        System.assertNotEquals(null, billingRequest.project, 'A project must be sent to the billing service.');
        System.assertNotEquals(null, billingRequest.project.projectid, 'The project ID must be included.');
        System.assertNotEquals(null, billingRequest.project.billAmount, 'The billing amount must be included.');
        System.assertNotEquals(null, billingRequest.project.username, 'The credential username must be included.');
        System.assertNotEquals(null, billingRequest.project.password, 'The credential password must be included.');
        System.assertEquals(
            'callout:IntegrationSB__BillingInvoiceService',
            endpoint,
            'The SOAP proxy must use the billing Named Credential.'
        );

        if (shouldThrowError) {
            throw new BillingMockException('Simulated billing service failure.');
        }

        BillingServiceProxy.billProjectResponse_element billingResponse =
            new BillingServiceProxy.billProjectResponse_element();
        billingResponse.status = responseStatus;
        response.put('response_x', billingResponse);
    }

    private class BillingMockException extends Exception {
    }
}
