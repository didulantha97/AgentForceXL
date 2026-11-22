// Demo data loader. Template for `scripts/pms-package.sh demo-data` and the sample-data step of `bootstrap`.
// The script fills in the placeholders (namespace of the target org, action, pack) and runs it with
// `sf apex run`. Do not run it by hand with the placeholders in place.
//
// PMS_DemoDataApi is the one global class of PMS Core (a System.Callable): anonymous Apex cannot call a
// public class of a packaged namespace. All checks (not production, admin only, licence) happen inside
// PMS_DemoData. Output lines start with PMS_DEMO| so the script can pick them out of the debug log.
String ns = '@@NS@@';
String action = '@@ACTION@@';
String pack = '@@PACK@@';
if (action == 'allow') {
  // Opt-in for Developer Edition / trial orgs. The script only does this for orgs it has already vetted.
  String pre = String.isBlank(ns) ? '' : ns + '__';
  Schema.SObjectType st = Schema.getGlobalDescribe().get(pre + 'PMS_Settings__c');
  if (st == null) {
    System.debug('PMS_DEMO|error|PMS Settings was not found in this org (is PMS Core deployed?).');
  } else {
    Id orgId = UserInfo.getOrganizationId();
    List<SObject> rows = Database.query('SELECT Id FROM ' + pre + 'PMS_Settings__c WHERE SetupOwnerId = :orgId LIMIT 1');
    SObject setting = rows.isEmpty() ? st.newSObject() : rows[0];
    if (rows.isEmpty()) {
      setting.put('SetupOwnerId', orgId);
    }
    setting.put(pre + 'Demo_Data_Allowed__c', true);
    upsert setting;
    System.debug('PMS_DEMO|message|Demo data allowed in this org.');
  }
} else {
Type apiType = Type.forName(String.isBlank(ns) ? null : ns, 'PMS_DemoDataApi');
if (apiType == null) {
  System.debug(
    'PMS_DEMO|error|PMS_DemoDataApi was not found in this org (is PMS Core deployed?).'
  );
} else {
  Callable api = (Callable) apiType.newInstance();
  api.call(action, new Map<String, Object>{ 'pack' => pack });
}
}
