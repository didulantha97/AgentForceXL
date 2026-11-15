/**
 * Gives portal users the permission sets their portal needs, automatically, when a user on a PMS portal
 * profile is created, activated or moved onto that profile (from PMS_UserTrigger):
 *   PMS Customer Portal User  ->  PMS_Stripe_Access (Stripe named credential principal; Pay now fails without it)
 *                                 PMS_Customer_Portal (documents, e-signature, check-in and approvals controller)
 *   PMS Partner Portal User   ->  PMS_Partner_Portal (access to the partner portal's Apex controller)
 * Runs in @future so it never collides with the DML that created the user.
 */
public without sharing class PMS_PortalUserSetup {
  public static final String PORTAL_PROFILE = 'PMS Customer Portal User';
  public static final String STRIPE_PERMSET = 'PMS_Stripe_Access';
  public static final String PARTNER_PROFILE = 'PMS Partner Portal User';
  public static final String PARTNER_PERMSET = 'PMS_Partner_Portal';
  public static final String CUSTOMER_PERMSET = 'PMS_Customer_Portal';
  /** The first (main) permission set per profile; kept for code written against the earlier version. */
  public static final Map<String, String> PERMSET_BY_PROFILE = new Map<String, String>{
    PORTAL_PROFILE => STRIPE_PERMSET,
    PARTNER_PROFILE => PARTNER_PERMSET
  };
  public static final Map<String, List<String>> PERMSETS_BY_PROFILE = new Map<String, List<String>>{
    PORTAL_PROFILE => new List<String>{ STRIPE_PERMSET, CUSTOMER_PERMSET },
    PARTNER_PROFILE => new List<String>{ PARTNER_PERMSET }
  };

  public static void onUsers(List<User> users, Map<Id, User> oldMap) {
    Set<Id> candidates = new Set<Id>();
    for (User u : users) {
      User old = oldMap == null ? null : oldMap.get(u.Id);
      Boolean relevant =
        u.IsActive &&
        u.ContactId != null &&
        (old == null ||
        old.ProfileId != u.ProfileId ||
        old.IsActive != u.IsActive);
      if (relevant) {
        candidates.add(u.Id);
      }
    }
    if (candidates.isEmpty()) {
      return;
    }
    if (System.isFuture() || System.isBatch() || System.isQueueable()) {
      assign(candidates);
    } else {
      assignAsync(candidates);
    }
  }

  @future
  public static void assignAsync(Set<Id> userIds) {
    assign(userIds);
  }

  public static void assign(Set<Id> userIds) {
    Set<String> names = new Set<String>();
    for (List<String> l : PERMSETS_BY_PROFILE.values()) {
      names.addAll(l);
    }
    Map<String, Id> permSetIds = new Map<String, Id>();
    for (PermissionSet ps : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE Name IN :names
    ]) {
      permSetIds.put(ps.Name, ps.Id);
    }
    if (permSetIds.isEmpty()) {
      return;
    }
    Set<String> already = new Set<String>();
    for (PermissionSetAssignment a : [
      SELECT AssigneeId, PermissionSetId
      FROM PermissionSetAssignment
      WHERE PermissionSetId IN :permSetIds.values() AND AssigneeId IN :userIds
    ]) {
      already.add(a.AssigneeId + ':' + a.PermissionSetId);
    }
    List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
    for (User u : [
      SELECT Id, Profile.Name
      FROM User
      WHERE
        Id IN :userIds
        AND IsActive = TRUE
        AND Profile.Name IN :PERMSETS_BY_PROFILE.keySet()
    ]) {
      for (String psName : PERMSETS_BY_PROFILE.get(u.Profile.Name)) {
        Id psId = permSetIds.get(psName);
        if (psId != null && !already.contains(u.Id + ':' + psId)) {
          toAdd.add(
            new PermissionSetAssignment(
              AssigneeId = u.Id,
              PermissionSetId = psId
            )
          );
        }
      }
    }
    if (!toAdd.isEmpty()) {
      for (Database.SaveResult r : Database.insert(toAdd, false)) {
        if (!r.isSuccess()) {
          System.debug(
            LoggingLevel.ERROR,
            'PMS portal user setup: ' + r.getErrors()
          );
        }
      }
    }
  }
}
