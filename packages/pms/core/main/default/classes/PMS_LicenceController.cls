/**
 * Back end of the licence banner and key card (LWC pmsLicenceBanner).
 * getStatus is open to anyone with access to the page; saving a key needs PMS_Manage_License.
 * PMS_License__c is a protected setting, so access is gated by the custom permission, not FLS.
 */
public with sharing class PMS_LicenceController {
  public class Status {
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Integer daysRemaining;
    @AuraEnabled
    public String edition;
    @AuraEnabled
    public Map<String, Boolean> modules;
    @AuraEnabled
    public String bannerText;
    @AuraEnabled
    public String endDate;
    @AuraEnabled
    public Boolean canManage;
  }

  @TestVisible
  private static Boolean manageOverride;

  @AuraEnabled(cacheable=true)
  public static Status getStatus() {
    return build();
  }

  @AuraEnabled
  public static Status saveLicenceKey(String token) {
    if (!PMS_Entitlements.keyEntryAllowed()) {
      throw fail(
        'Licence key entry is disabled for a suspended account. Contact your PMS provider.'
      );
    }
    if (!canManage()) {
      throw fail(
        'You need the PMS Manage License permission to change the licence key.'
      );
    }
    String clean = token == null ? '' : token.replaceAll('\\s+', '');
    if (clean.length() > 1020) {
      throw fail('The licence key is too long.');
    }
    PMS_Entitlements.TokenInfo info = PMS_Entitlements.inspect(clean);
    if (!info.valid) {
      throw fail(info.error);
    }
    if (PMS_Entitlements.today() > PMS_Entitlements.lastUsableDay(info)) {
      throw fail(
        'This licence key expired on ' +
          PMS_Entitlements.lastUsableDay(info).format() +
          '.'
      );
    }
    String replay = PMS_Entitlements.replayError(info);
    if (replay != null) {
      throw fail(replay);
    }
    PMS_Entitlements.storeToken(clean);
    return build();
  }

  private static AuraHandledException fail(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message); // otherwise tests and some callers only see "Script-thrown exception"
    return e;
  }

  private static Boolean canManage() {
    return manageOverride != null
      ? manageOverride
      : FeatureManagement.checkPermission('PMS_Manage_License');
  }

  private static Status build() {
    Status s = new Status();
    s.state = PMS_Entitlements.state();
    s.daysRemaining = PMS_Entitlements.daysRemaining();
    s.edition = PMS_Entitlements.edition();
    s.modules = PMS_Entitlements.modules();
    s.bannerText = PMS_Entitlements.bannerText();
    s.endDate = PMS_Entitlements.endDateLabel();
    s.canManage = canManage();
    return s;
  }
}
