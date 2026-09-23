public class RewardsCalloutService{

    public static Integer submitUsersForRewardCallout(String jsonBody) {
        //Set Endpoint from Named Credential IntegrationSB__BalancedLiving
        String endpoint = 'callout:IntegrationSB__BalancedLiving/rewards';
        
        //Make HTTP Callout
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonBody);
        Http http = new Http();
        HttpResponse res = http.send(req);
        Integer statusCode = res.getStatusCode();
        
        //Update to return response status code
        return statusCode;
    }
}