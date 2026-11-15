/**
 * Customer portal users need the PMS Stripe Access permission set (it holds the Stripe named
 * credential principal), or Pay now fails. This assigns it automatically when a user on the
 * PMS Customer Portal User profile is created, activated or moved onto that profile.
 * Runs in @future so it never collides with the DML that created the user.
 */
public without sharing class PMS_PortalUserSetup {
  public static final String PORTAL_PROFILE = 'PMS Customer Portal User';
  public static final String STRIPE_PERMSET = 'PMS_Stripe_Access';

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
    List<PermissionSet> ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :STRIPE_PERMSET
      LIMIT 1
    ];
    if (ps.isEmpty()) {
      return;
    }
    Set<Id> already = new Set<Id>();
    for (PermissionSetAssignment a : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE PermissionSetId = :ps[0].Id AND AssigneeId IN :userIds
    ]) {
      already.add(a.AssigneeId);
    }
    List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
    for (User u : [
      SELECT Id
      FROM User
      WHERE
        Id IN :userIds
        AND IsActive = TRUE
        AND Profile.Name = :PORTAL_PROFILE
    ]) {
      if (!already.contains(u.Id)) {
        toAdd.add(
          new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = ps[0].Id
          )
        );
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
