/**
 * Back end of the demo data card (LWC pmsDemoDataCard). Every method re-checks the same guards as
 * PMS_DemoData (not production, admin only, licence not suspended), so the card hiding itself is a courtesy,
 * not the protection. All three calls return the fresh status; "message" carries what happened.
 */
public with sharing class PMS_DemoDataController {
  @AuraEnabled
  public static PMS_DemoData.Status getStatus() {
    return PMS_DemoData.status();
  }

  @AuraEnabled
  public static PMS_DemoData.Status load(String pack) {
    return withMessage(PMS_DemoData.load(pack));
  }

  @AuraEnabled
  public static PMS_DemoData.Status reset(String pack) {
    return withMessage(PMS_DemoData.reset(pack));
  }

  private static PMS_DemoData.Status withMessage(String message) {
    PMS_DemoData.Status st = PMS_DemoData.status();
    st.message = message;
    return st;
  }
}
