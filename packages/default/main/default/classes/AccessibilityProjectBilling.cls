global class AccessibilityProjectBilling {
    
    @future(callout=true)
    public static void callBillingService(String projectId, Decimal billingAmount) {
        // 1. Instantiate the SOAP service port generated from your WSDL
        BillingServiceProxy.InvoicesPortSoap11 stub = new BillingServiceProxy.InvoicesPortSoap11();
        
        // 2. Instantiate the project object model and populate the required parameters
        BillingServiceProxy.project project = new BillingServiceProxy.project();
        project.projectid = projectId;
        project.billAmount = Double.valueOf(billingAmount);
        
        // 3. Bind the Named Credentials dynamically per challenge requirements
        project.username = '{!$Credential.BillingServiceCredential.username}';
        project.password = '{!$Credential.BillingServiceCredential.password}';
        
        try {
            // 4. Fire the SOAP callout method
            String status = stub.billProject(project);
            
            // 5. Update record status to 'Complete' upon success
            if (status == 'ok' || status == 'OK') {
                Accessibility_Project__c accProject = [
                    SELECT Id, Status__c 
                    FROM Accessibility_Project__c 
                    WHERE Id = :projectId 
                    LIMIT 1
                ];
                accProject.Status__c = 'Complete';
                update accProject;
            }
        } catch (Exception e) {
            System.debug('SOAP Callout Failed: ' + e.getMessage());
        }
    }
}
