/**
 * Keeps one public group per Access Team (DeveloperName PMS_Team_<team id>) in line with the team's
 * members, and assigns the PMS Hide Amounts / PMS Hide Customer Details permission sets from the
 * teams' "Hide ..." settings. Optionally starts a full share recalculation afterwards.
 *
 * Group, GroupMember and PermissionSetAssignment are setup objects, so this runs as its own
 * queueable transaction (no mixed DML with the team records that triggered it).
 */
public without sharing class PMS_AccessGroupSync implements Queueable {
  final Set<Id> teamIds; // null = every team
  final Boolean recalcAfter;

  @TestVisible
  static Boolean runBatchInTests = false;

  public PMS_AccessGroupSync(Set<Id> teamIds, Boolean recalcAfter) {
    this.teamIds = teamIds;
    this.recalcAfter = recalcAfter == true;
  }

  public void execute(QueueableContext ctx) {
    syncGroups();
    syncHidePermissionSets();
    if (recalcAfter && (!Test.isRunningTest() || runBatchInTests)) {
      Database.executeBatch(new PMS_AccessRecalcBatch(), 200);
    }
  }

  // ------------------------------------------------------------------ groups

  public void syncGroups() {
    List<PMS_Access_Team__c> teams = teamIds == null
      ? [
          SELECT Id, Name, Active__c, All_Internal_Users__c
          FROM PMS_Access_Team__c
        ]
      : [
          SELECT Id, Name, Active__c, All_Internal_Users__c
          FROM PMS_Access_Team__c
          WHERE Id IN :teamIds
        ];

    // Which groups should exist, by DeveloperName
    Map<String, PMS_Access_Team__c> wanted = new Map<String, PMS_Access_Team__c>();
    for (PMS_Access_Team__c t : teams) {
      if (t.Active__c && !t.All_Internal_Users__c) {
        wanted.put(PMS_AccessService.teamGroupName(t.Id), t);
      }
    }
    Set<String> inScope = new Set<String>(wanted.keySet());
    if (teamIds != null) {
      for (Id tid : teamIds) {
        inScope.add(PMS_AccessService.teamGroupName(tid));
      }
    }

    Map<String, Group> existing = new Map<String, Group>();
    String prefix = PMS_AccessService.TEAM_GROUP_PREFIX + '%';
    List<Group> found = teamIds == null
      ? [
          SELECT Id, DeveloperName, Name
          FROM Group
          WHERE Type = 'Regular' AND DeveloperName LIKE :prefix
        ]
      : [
          SELECT Id, DeveloperName, Name
          FROM Group
          WHERE Type = 'Regular' AND DeveloperName IN :inScope
        ];
    for (Group g : found) {
      existing.put(g.DeveloperName, g);
    }

    // Create missing groups, rename changed ones, delete groups of removed / inactive teams
    List<Group> upserts = new List<Group>();
    for (String dev : wanted.keySet()) {
      String label = ('PMS Team: ' + wanted.get(dev).Name).left(40);
      Group g = existing.get(dev);
      if (g == null) {
        upserts.add(
          new Group(
            Name = label,
            DeveloperName = dev,
            Type = 'Regular',
            DoesIncludeBosses = false
          )
        );
      } else if (g.Name != label) {
        g.Name = label;
        upserts.add(g);
      }
    }
    List<Group> deletes = new List<Group>();
    for (String dev : existing.keySet()) {
      if (!wanted.containsKey(dev)) {
        deletes.add(existing.get(dev));
      }
    }
    if (!upserts.isEmpty()) {
      upsert upserts;
      for (Group g : upserts) {
        existing.put(g.DeveloperName, g);
      }
    }
    if (!deletes.isEmpty()) {
      delete deletes;
    }

    // Members
    Map<Id, Id> groupByTeam = new Map<Id, Id>();
    for (String dev : wanted.keySet()) {
      groupByTeam.put(wanted.get(dev).Id, existing.get(dev).Id);
    }
    if (groupByTeam.isEmpty()) {
      return;
    }
    Map<Id, Set<Id>> desired = new Map<Id, Set<Id>>();
    for (Id gid : groupByTeam.values()) {
      desired.put(gid, new Set<Id>());
    }
    for (
      PMS_Access_Team_Member__c m : PMS_AccessService.activeMemberships(null)
    ) {
      Id gid = groupByTeam.get(m.Team__c);
      if (gid != null) {
        desired.get(gid).add(m.User__c);
      }
    }
    Set<Id> gids = desired.keySet();
    List<GroupMember> removeMembers = new List<GroupMember>();
    Map<Id, Set<Id>> have = new Map<Id, Set<Id>>();
    for (GroupMember gm : [
      SELECT Id, GroupId, UserOrGroupId
      FROM GroupMember
      WHERE GroupId IN :gids
    ]) {
      if (!have.containsKey(gm.GroupId)) {
        have.put(gm.GroupId, new Set<Id>());
      }
      have.get(gm.GroupId).add(gm.UserOrGroupId);
      if (!desired.get(gm.GroupId).contains(gm.UserOrGroupId)) {
        removeMembers.add(gm);
      }
    }
    List<GroupMember> addMembers = new List<GroupMember>();
    for (Id gid : desired.keySet()) {
      for (Id uid : desired.get(gid)) {
        if (!have.containsKey(gid) || !have.get(gid).contains(uid)) {
          addMembers.add(new GroupMember(GroupId = gid, UserOrGroupId = uid));
        }
      }
    }
    if (!removeMembers.isEmpty()) {
      delete removeMembers;
    }
    if (!addMembers.isEmpty()) {
      insert addMembers;
    }
  }

  // ------------------------------------------------------------------ hide permission sets

  /** A user gets a Hide permission set when any of their active teams has that setting ticked. */
  public void syncHidePermissionSets() {
    Map<String, PermissionSet> sets = new Map<String, PermissionSet>();
    for (PermissionSet ps : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE Name IN ('PMS_Hide_Amounts', 'PMS_Hide_Customer_Details')
    ]) {
      sets.put(ps.Name, ps);
    }
    if (sets.size() < 2) {
      return;
    }
    Set<Id> hideAmounts = new Set<Id>();
    Set<Id> hideCustomer = new Set<Id>();
    for (
      PMS_Access_Team_Member__c m : PMS_AccessService.activeMemberships(null)
    ) {
      if (m.Team__r.All_Internal_Users__c) {
        continue; // "everyone" teams have no member list to hide from
      }
      if (m.Team__r.Hide_Amounts__c) {
        hideAmounts.add(m.User__c);
      }
      if (m.Team__r.Hide_Customer_Details__c) {
        hideCustomer.add(m.User__c);
      }
    }
    Map<Id, Set<Id>> desired = new Map<Id, Set<Id>>{
      sets.get('PMS_Hide_Amounts').Id => hideAmounts,
      sets.get('PMS_Hide_Customer_Details').Id => hideCustomer
    };
    Set<Id> psIds = desired.keySet();
    List<PermissionSetAssignment> remove = new List<PermissionSetAssignment>();
    Map<Id, Set<Id>> have = new Map<Id, Set<Id>>();
    for (PermissionSetAssignment a : [
      SELECT Id, PermissionSetId, AssigneeId
      FROM PermissionSetAssignment
      WHERE PermissionSetId IN :psIds
    ]) {
      if (!have.containsKey(a.PermissionSetId)) {
        have.put(a.PermissionSetId, new Set<Id>());
      }
      have.get(a.PermissionSetId).add(a.AssigneeId);
      if (!desired.get(a.PermissionSetId).contains(a.AssigneeId)) {
        remove.add(a);
      }
    }
    List<PermissionSetAssignment> add = new List<PermissionSetAssignment>();
    for (Id psId : desired.keySet()) {
      for (Id uid : desired.get(psId)) {
        if (!have.containsKey(psId) || !have.get(psId).contains(uid)) {
          add.add(
            new PermissionSetAssignment(
              PermissionSetId = psId,
              AssigneeId = uid
            )
          );
        }
      }
    }
    if (!remove.isEmpty()) {
      Database.delete(remove, false);
    }
    if (!add.isEmpty()) {
      Database.insert(add, false);
    }
  }
}
