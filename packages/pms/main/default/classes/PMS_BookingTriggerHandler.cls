/**
 * Booking trigger logic:
 *  - before: default Site from Space, block double bookings (also within the same batch)
 *  - after (hotel reservations): keep Room Nights and Inventory Days in step
 */
public without sharing class PMS_BookingTriggerHandler {
  public static Boolean bypass = false;

  public static void beforeSave(
    List<PMS_Booking__c> records,
    Map<Id, PMS_Booking__c> oldMap
  ) {
    if (bypass) {
      return;
    }
    defaultSiteFromSpace(records);
    preventOverlaps(records, oldMap);
  }

  public static void afterSave(
    List<PMS_Booking__c> records,
    Map<Id, PMS_Booking__c> oldMap
  ) {
    if (bypass) {
      return;
    }
    Id reservationRt = PMS_ModuleConfig.recordTypeId(
      PMS_Booking__c.SObjectType,
      'Reservation'
    );
    List<PMS_Booking__c> changed = new List<PMS_Booking__c>();
    Set<Id> typeIds = new Set<Id>();
    Date minDate;
    Date maxDate;
    for (PMS_Booking__c b : records) {
      if (b.RecordTypeId != reservationRt) {
        continue;
      }
      PMS_Booking__c old = oldMap == null ? null : oldMap.get(b.Id);
      Boolean relevant =
        old == null ||
        old.Start__c != b.Start__c ||
        old.End__c != b.End__c ||
        old.Status__c != b.Status__c ||
        old.Space__c != b.Space__c ||
        old.Room_Type_Requested__c != b.Room_Type_Requested__c ||
        old.Rate_Plan__c != b.Rate_Plan__c;
      if (!relevant) {
        continue;
      }
      changed.add(b);
      typeIds.add(b.Room_Type_Requested__c);
      for (
        PMS_Booking__c x : old == null
          ? new List<PMS_Booking__c>{ b }
          : new List<PMS_Booking__c>{ b, old }
      ) {
        typeIds.add(x.Room_Type_Requested__c);
        if (x.Start__c != null) {
          Date s = x.Start__c.date().addDays(-1);
          minDate = minDate == null || s < minDate ? s : minDate;
        }
        if (x.End__c != null) {
          Date e = x.End__c.date().addDays(1);
          maxDate = maxDate == null || e > maxDate ? e : maxDate;
        }
      }
    }
    if (changed.isEmpty()) {
      return;
    }
    PMS_BookingService.syncRoomNights(changed);
    for (PMS_Booking__c b : [
      SELECT Space__r.Space_Type__c
      FROM PMS_Booking__c
      WHERE Id IN :changed AND Space__c != NULL
    ]) {
      typeIds.add(b.Space__r.Space_Type__c);
    }
    PMS_BookingService.refreshInventory(typeIds, minDate, maxDate);
  }

  public static void afterDelete(List<PMS_Booking__c> oldRecords) {
    if (bypass) {
      return;
    }
    Set<Id> typeIds = new Set<Id>();
    Date minDate;
    Date maxDate;
    for (PMS_Booking__c b : oldRecords) {
      if (
        b.Room_Type_Requested__c == null ||
        b.Start__c == null ||
        b.End__c == null
      ) {
        continue;
      }
      typeIds.add(b.Room_Type_Requested__c);
      minDate = minDate == null ||
        b.Start__c.date() < minDate
        ? b.Start__c.date()
        : minDate;
      maxDate = maxDate == null ||
        b.End__c.date() > maxDate
        ? b.End__c.date().addDays(1)
        : maxDate;
    }
    PMS_BookingService.refreshInventory(typeIds, minDate, maxDate);
  }

  private static void defaultSiteFromSpace(List<PMS_Booking__c> records) {
    Set<Id> spaceIds = new Set<Id>();
    for (PMS_Booking__c b : records) {
      if (b.Site__c == null && b.Space__c != null) {
        spaceIds.add(b.Space__c);
      }
    }
    if (spaceIds.isEmpty()) {
      return;
    }
    Map<Id, PMS_Space__c> spaces = new Map<Id, PMS_Space__c>(
      [SELECT Id, Site__c FROM PMS_Space__c WHERE Id IN :spaceIds]
    );
    for (PMS_Booking__c b : records) {
      if (b.Site__c == null && spaces.containsKey(b.Space__c)) {
        b.Site__c = spaces.get(b.Space__c).Site__c;
      }
    }
  }

  private static void preventOverlaps(
    List<PMS_Booking__c> records,
    Map<Id, PMS_Booking__c> oldMap
  ) {
    List<PMS_Booking__c> toCheck = new List<PMS_Booking__c>();
    Set<Id> spaceIds = new Set<Id>();
    Set<Id> selfIds = new Set<Id>();
    Datetime minStart;
    Datetime maxEnd;
    for (PMS_Booking__c b : records) {
      if (b.Space__c == null || b.Start__c == null || b.End__c == null) {
        continue;
      }
      if (b.End__c <= b.Start__c) {
        b.End__c.addError('End must be after Start.');
        continue;
      }
      if (PMS_AvailabilityService.NON_BLOCKING_STATUSES.contains(b.Status__c)) {
        continue;
      }
      PMS_Booking__c old = oldMap == null ? null : oldMap.get(b.Id);
      if (
        old != null &&
        old.Space__c == b.Space__c &&
        old.Start__c == b.Start__c &&
        old.End__c == b.End__c &&
        old.Status__c == b.Status__c
      ) {
        continue;
      }
      toCheck.add(b);
      spaceIds.add(b.Space__c);
      if (b.Id != null) {
        selfIds.add(b.Id);
      }
      minStart = minStart == null ||
        b.Start__c < minStart
        ? b.Start__c
        : minStart;
      maxEnd = maxEnd == null || b.End__c > maxEnd ? b.End__c : maxEnd;
    }
    if (toCheck.isEmpty()) {
      return;
    }
    List<PMS_Booking__c> existing = [
      SELECT Id, Name, Space__c, Start__c, End__c
      FROM PMS_Booking__c
      WHERE
        Space__c IN :spaceIds
        AND Start__c < :maxEnd
        AND End__c > :minStart
        AND Status__c NOT IN :PMS_AvailabilityService.NON_BLOCKING_STATUSES
        AND Id NOT IN :selfIds
    ];
    for (Integer i = 0; i < toCheck.size(); i++) {
      PMS_Booking__c b = toCheck[i];
      for (PMS_Booking__c e : existing) {
        if (
          e.Space__c == b.Space__c &&
          e.Start__c < b.End__c &&
          e.End__c > b.Start__c
        ) {
          b.Space__c.addError(
            'Already booked by ' + e.Name + ' for an overlapping period.'
          );
          break;
        }
      }
      for (Integer j = 0; j < i; j++) {
        PMS_Booking__c o = toCheck[j];
        if (
          o.Space__c == b.Space__c &&
          o.Start__c < b.End__c &&
          o.End__c > b.Start__c
        ) {
          b.Space__c.addError('Overlaps another booking in the same save.');
          break;
        }
      }
    }
  }
}
