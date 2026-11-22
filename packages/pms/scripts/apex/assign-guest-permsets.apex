// Gives Experience site guest users the PMS permission sets they need.
// Run by scripts/pms-package.sh org-setup after the sites are deployed. Safe to re-run.
// __NAMESPACE__ is replaced by the script with the package namespace ('' for source deploys).
String ns = '__NAMESPACE__';
// PMS_Payments gets the Stripe webhook (PMS_Payment_Integration) but not the generic gateway webhook
// (PMS_Payment_Gateway / PMS_PaymentWebhook): nothing in PMS posts to it, so a public endpoint is not needed.
Map<String, List<String>> permSetsBySite = new Map<String, List<String>>{
  'PMS_Booking' => new List<String>{ 'PMS_Public_Booking', 'PMS_Stripe_Access' },
  'PMS_Payments' => new List<String>{ 'PMS_Payment_Link', 'PMS_Payment_Integration' }
};
Set<String> psNames = new Set<String>();
for (List<String> names : permSetsBySite.values()) {
  psNames.addAll(names);
}
Map<String, Id> psIds = new Map<String, Id>();
for (PermissionSet ps : [
  SELECT Id, Name
  FROM PermissionSet
  WHERE Name IN :psNames AND NamespacePrefix = :(String.isBlank(ns) ? null : ns)
]) {
  psIds.put(ps.Name, ps.Id);
}
List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
for (Site s : [SELECT Name, GuestUserId FROM Site WHERE Name IN :permSetsBySite.keySet()]) {
  if (s.GuestUserId == null) {
    continue;
  }
  Set<Id> have = new Set<Id>();
  for (PermissionSetAssignment psa : [
    SELECT PermissionSetId
    FROM PermissionSetAssignment
    WHERE AssigneeId = :s.GuestUserId
  ]) {
    have.add(psa.PermissionSetId);
  }
  for (String name : permSetsBySite.get(s.Name)) {
    Id psId = psIds.get(name);
    if (psId != null && !have.contains(psId)) {
      toAdd.add(new PermissionSetAssignment(AssigneeId = s.GuestUserId, PermissionSetId = psId));
    }
  }
}
insert toAdd;
System.debug('PMS guest permission set assignments added: ' + toAdd.size());
