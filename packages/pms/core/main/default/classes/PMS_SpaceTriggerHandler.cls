/**
 * Space trigger logic: licence caps on new rooms (maxRooms) and units (maxUnits).
 * Runs on insert and when a record type changes into a capped type. Without sharing so the cap counts every record, not just the user's.
 */
public without sharing class PMS_SpaceTriggerHandler {
  public static void beforeInsert(List<PMS_Space__c> records) {
    enforce(records);
  }

  /** A record type change into Room or Unit adds to that type's count, so it is capped like an insert. */
  public static void beforeUpdate(
    List<PMS_Space__c> records,
    Map<Id, PMS_Space__c> oldMap
  ) {
    List<PMS_Space__c> moved = new List<PMS_Space__c>();
    for (PMS_Space__c sp : records) {
      PMS_Space__c old = oldMap == null ? null : oldMap.get(sp.Id);
      if (old != null && sp.RecordTypeId != old.RecordTypeId) {
        moved.add(sp);
      }
    }
    if (!moved.isEmpty()) {
      enforce(moved); // enforce() ignores types that are not capped
    }
  }

  /** Records the pilot start on the first space created, where DML is allowed. Never blocks the save. */
  public static void afterInsert() {
    try {
      PMS_Entitlements.ensureInstallDate();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'PMS install date not recorded: ' + e.getMessage()
      );
    }
  }

  private static void enforce(List<PMS_Space__c> records) {
    Map<String, Id> typeIds = new Map<String, Id>{
      'Room' => PMS_ModuleConfig.recordTypeId(PMS_Space__c.SObjectType, 'Room'),
      'Unit' => PMS_ModuleConfig.recordTypeId(PMS_Space__c.SObjectType, 'Unit')
    };
    Map<String, Integer> room = new Map<String, Integer>();
    Map<String, String> messages = new Map<String, String>();
    for (PMS_Space__c sp : records) {
      String what = sp.RecordTypeId == null
        ? null
        : (sp.RecordTypeId == typeIds.get('Room')
            ? 'Room'
            : (sp.RecordTypeId == typeIds.get('Unit') ? 'Unit' : null));
      if (what == null) {
        continue;
      }
      if (!room.containsKey(what)) {
        // One COUNT per type per trigger run; null = unlimited.
        room.put(what, PMS_Entitlements.remaining(what));
      }
      Integer left = room.get(what);
      if (left == null) {
        continue;
      }
      if (left <= 0) {
        if (!messages.containsKey(what)) {
          messages.put(what, PMS_Entitlements.limitMessage(what)); // once per type, not per record
        }
        sp.addError(messages.get(what));
      } else {
        room.put(what, left - 1);
      }
    }
  }
}
