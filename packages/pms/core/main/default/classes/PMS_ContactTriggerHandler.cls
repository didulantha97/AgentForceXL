/**
 * Contact trigger logic for guest matching. When staff dismiss a possible-duplicate flag (Possible Duplicate Of
 * goes from a contact to blank), the system-maintained Duplicate Reason is cleared with it.
 * Contact is a standard object shared with the whole client org: no licence check, no SOQL, no DML, and
 * this handler never throws, so it can never block a Contact save. Runs in system context, so it also works
 * for users who only have read access to the reason field.
 */
public with sharing class PMS_ContactTriggerHandler {
  public static void beforeUpdate(
    List<Contact> records,
    Map<Id, Contact> oldMap
  ) {
    if (records == null || oldMap == null) {
      return;
    }
    try {
      for (Contact c : records) {
        Contact old = oldMap.get(c.Id);
        if (
          old != null &&
          old.PMS_Possible_Duplicate_Of__c != null &&
          c.PMS_Possible_Duplicate_Of__c == null &&
          c.PMS_Duplicate_Reason__c != null
        ) {
          c.PMS_Duplicate_Reason__c = null;
        }
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'PMS duplicate reason not cleared: ' + e.getMessage()
      );
    }
  }
}
