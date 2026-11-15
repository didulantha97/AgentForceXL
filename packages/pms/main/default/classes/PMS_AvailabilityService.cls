/**
 * Availability engine shared by all modules.
 * A space is busy when another booking on it overlaps [start, end) and is not
 * Inquiry / Cancelled / No Show.
 */
public inherited sharing class PMS_AvailabilityService {
  public static final Set<String> NON_BLOCKING_STATUSES = new Set<String>{
    'Inquiry',
    'Cancelled',
    'No Show'
  };
  public static final Set<String> UNSELLABLE_SPACE_STATUSES = new Set<String>{
    'Out of Order',
    'Under Renovation'
  };

  /** Returns the ids (from the given set) that have an overlapping blocking booking. */
  public static Set<Id> busySpaceIds(
    Set<Id> spaceIds,
    Datetime startDt,
    Datetime endDt,
    Set<Id> excludeBookingIds
  ) {
    Set<Id> busy = new Set<Id>();
    if (
      spaceIds == null ||
      spaceIds.isEmpty() ||
      startDt == null ||
      endDt == null
    ) {
      return busy;
    }
    Set<Id> excluded = excludeBookingIds == null
      ? new Set<Id>()
      : excludeBookingIds;
    for (PMS_Booking__c b : [
      SELECT Id, Space__c
      FROM PMS_Booking__c
      WHERE
        Space__c IN :spaceIds
        AND Start__c < :endDt
        AND End__c > :startDt
        AND Status__c NOT IN :NON_BLOCKING_STATUSES
        AND Id NOT IN :excluded
    ]) {
      busy.add(b.Space__c);
    }
    return busy;
  }

  public static Boolean isSpaceAvailable(
    Id spaceId,
    Datetime startDt,
    Datetime endDt,
    Id excludeBookingId
  ) {
    Set<Id> excluded = excludeBookingId == null
      ? new Set<Id>()
      : new Set<Id>{ excludeBookingId };
    return !busySpaceIds(new Set<Id>{ spaceId }, startDt, endDt, excluded)
      .contains(spaceId);
  }

  /**
   * Free, sellable spaces at a site (optionally of one type) for the period,
   * able to hold the given number of occupants.
   */
  public static List<PMS_Space__c> findAvailableSpaces(
    Id siteId,
    Id spaceTypeId,
    Datetime startDt,
    Datetime endDt,
    Integer occupants
  ) {
    Integer guests = occupants == null ? 0 : occupants;
    String soql =
      'SELECT Id, Name, Site__c, Space_Type__c, Space_Type__r.Name, Floor__c, Max_Occupancy__c, ' +
      'Base_Rate__c, Operational_Status__c, RecordType.DeveloperName ' +
      'FROM PMS_Space__c WHERE Site__c = :siteId AND Bookable__c = true ' +
      'AND Operational_Status__c NOT IN :UNSELLABLE_SPACE_STATUSES';
    if (spaceTypeId != null) {
      soql += ' AND Space_Type__c = :spaceTypeId';
    }
    soql += ' ORDER BY Name LIMIT 500';
    List<PMS_Space__c> candidates = Database.query(soql);

    Map<Id, PMS_Space__c> byId = new Map<Id, PMS_Space__c>();
    for (PMS_Space__c s : candidates) {
      if (s.Max_Occupancy__c == null || s.Max_Occupancy__c >= guests) {
        byId.put(s.Id, s);
      }
    }
    Set<Id> busy = busySpaceIds(byId.keySet(), startDt, endDt, null);
    List<PMS_Space__c> free = new List<PMS_Space__c>();
    for (PMS_Space__c s : byId.values()) {
      if (!busy.contains(s.Id)) {
        free.add(s);
      }
    }
    return free;
  }

  /** Count of free rooms per space type at a site, used by the booking engine and the AI agent. */
  public static Map<Id, Integer> availableCountByType(
    Id siteId,
    Datetime startDt,
    Datetime endDt,
    Integer occupants
  ) {
    Map<Id, Integer> counts = new Map<Id, Integer>();
    for (
      PMS_Space__c s : findAvailableSpaces(
        siteId,
        null,
        startDt,
        endDt,
        occupants
      )
    ) {
      if (s.Space_Type__c == null) {
        continue;
      }
      Integer c = counts.containsKey(s.Space_Type__c)
        ? counts.get(s.Space_Type__c)
        : 0;
      counts.put(s.Space_Type__c, c + 1);
    }
    return counts;
  }
}
