/** Agent action: "Check Availability" for a site, type and dates. */
public with sharing class PMS_CheckAvailabilityAction {
  @InvocableMethod(
    label='PMS: Check Availability'
    description='Checks how many rooms, units or resources are free at a site for the given dates and guests.'
    category='Unified PMS'
  )
  public static List<PMS_AgentActions.AvailabilityResult> run(
    List<PMS_AgentActions.AvailabilityRequest> requests
  ) {
    List<PMS_AgentActions.AvailabilityResult> results = new List<PMS_AgentActions.AvailabilityResult>();
    for (PMS_AgentActions.AvailabilityRequest r : requests) {
      results.add(PMS_AgentActions.checkAvailability(r));
    }
    return results;
  }
}
