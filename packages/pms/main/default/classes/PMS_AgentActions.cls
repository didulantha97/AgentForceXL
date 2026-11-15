/**
 * Agentforce / Flow actions. Each inner class exposes one @InvocableMethod so it can be
 * added as an agent action ("Check Availability", "Get Price", "Create Booking").
 * Apex allows one @InvocableMethod per class, so each action lives in its own top-level
 * class below this one; this class holds the shared request/response types.
 */
public with sharing class PMS_AgentActions {
  public class AvailabilityRequest {
    @InvocableVariable(required=true label='Site Id')
    public Id siteId;
    @InvocableVariable(label='Space Type Id')
    public Id spaceTypeId;
    @InvocableVariable(required=true label='Start Date')
    public Date startDate;
    @InvocableVariable(required=true label='End Date')
    public Date endDate;
    @InvocableVariable(label='Number of Guests')
    public Integer guests;
  }

  public class AvailabilityResult {
    @InvocableVariable(label='Available')
    public Boolean available;
    @InvocableVariable(label='Available Count')
    public Integer availableCount;
    @InvocableVariable(label='Summary')
    public String summary;
  }

  public static AvailabilityResult checkAvailability(AvailabilityRequest r) {
    PMS_Site__c site = [
      SELECT Id, Time_Zone__c, Check_In_Time__c, Check_Out_Time__c
      FROM PMS_Site__c
      WHERE Id = :r.siteId
    ];
    Datetime s = PMS_DateUtil.toDatetime(
      r.startDate,
      site.Check_In_Time__c,
      site.Time_Zone__c
    );
    Datetime e = PMS_DateUtil.toDatetime(
      r.endDate,
      site.Check_Out_Time__c,
      site.Time_Zone__c
    );
    List<PMS_Space__c> free = PMS_AvailabilityService.findAvailableSpaces(
      r.siteId,
      r.spaceTypeId,
      s,
      e,
      r.guests
    );
    AvailabilityResult res = new AvailabilityResult();
    res.availableCount = free.size();
    res.available = !free.isEmpty();
    Map<String, Integer> byType = new Map<String, Integer>();
    for (PMS_Space__c sp : free) {
      String n = sp.Space_Type__r == null ? 'Other' : sp.Space_Type__r.Name;
      byType.put(n, (byType.containsKey(n) ? byType.get(n) : 0) + 1);
    }
    List<String> parts = new List<String>();
    for (String n : byType.keySet()) {
      parts.add(byType.get(n) + ' x ' + n);
    }
    res.summary = free.isEmpty()
      ? 'Nothing is available for ' + r.startDate + ' to ' + r.endDate + '.'
      : 'Available: ' + String.join(parts, ', ') + '.';
    return res;
  }
}
