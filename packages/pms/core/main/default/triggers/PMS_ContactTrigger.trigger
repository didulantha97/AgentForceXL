trigger PMS_ContactTrigger on Contact(before update) {
  // Standard object used by the whole org: deliberately no PMS_Entitlements.guardWrites(), a suspended licence must not block Contact saves.
  PMS_ContactTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
}
