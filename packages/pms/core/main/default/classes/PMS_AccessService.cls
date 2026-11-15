/**
 * PMS access engine.
 *
 * Business managers keep Access Teams (who) and Access Rules (which site / module / records, Read or Edit)
 * as ordinary records. This class turns them into Apex-managed sharing rows (row cause PMS_Access_Rule__c)
 * on every object listed in PMS_Access_Object__mdt.
 *
 * A rule only has an effect on an object whose internal sharing default is Private or Public Read Only.
 * While an object is Public Read/Write everyone can already edit it, so the engine skips it.
 *
 * Runs without sharing on purpose: it has to see every record to grant access to it.
 */
public without sharing class PMS_AccessService {
  public static final String ROW_CAUSE = 'PMS_Access_Rule__c';
  public static final String TEAM_GROUP_PREFIX = 'PMS_Team_';

  @TestVisible
  static Map<String, String> owdOverride = new Map<String, String>();
  @TestVisible
  static String rowCauseOverride;
  @TestVisible
  public static List<String> lastErrors = new List<String>();

  static Map<String, String> owdCache;
  static List<RuleInfo> ruleCache;
  static Boolean fullRecalcQueued = false;

  // ------------------------------------------------------------------ config

  public class RuleInfo {
    public Id ruleId;
    public Id teamId;
    public Id groupId;
    public Id siteId;
    public String module;
    public Set<String> keys = new Set<String>();
    public Boolean edit = false;
  }

  public static List<PMS_Access_Object__mdt> objectConfigs() {
    List<PMS_Access_Object__mdt> out = new List<PMS_Access_Object__mdt>();
    for (PMS_Access_Object__mdt c : PMS_Access_Object__mdt.getAll().values()) {
      if (c.Active__c) {
        out.add(c);
      }
    }
    // stable order
    List<String> keys = new List<String>();
    Map<String, PMS_Access_Object__mdt> byKey = new Map<String, PMS_Access_Object__mdt>();
    for (PMS_Access_Object__mdt c : out) {
      String k =
        String.valueOf(c.Sort_Order__c == null ? 9999 : c.Sort_Order__c)
          .leftPad(6, '0') + c.Object_API_Name__c;
      keys.add(k);
      byKey.put(k, c);
    }
    keys.sort();
    List<PMS_Access_Object__mdt> sorted = new List<PMS_Access_Object__mdt>();
    for (String k : keys) {
      sorted.add(byKey.get(k));
    }
    return sorted;
  }

  public static PMS_Access_Object__mdt configFor(String objectApi) {
    for (PMS_Access_Object__mdt c : objectConfigs()) {
      if (c.Object_API_Name__c == objectApi) {
        return c;
      }
    }
    return null;
  }

  /** Internal sharing default per configured object: Private, Read, ReadWrite or ControlledByParent. */
  public static Map<String, String> sharingDefaults() {
    if (owdCache == null) {
      owdCache = new Map<String, String>();
      Set<String> names = new Set<String>();
      for (PMS_Access_Object__mdt c : objectConfigs()) {
        names.add(c.Object_API_Name__c);
      }
      if (!names.isEmpty()) {
        for (EntityDefinition e : [
          SELECT QualifiedApiName, InternalSharingModel
          FROM EntityDefinition
          WHERE QualifiedApiName IN :names
        ]) {
          owdCache.put(e.QualifiedApiName, e.InternalSharingModel);
        }
      }
    }
    Map<String, String> merged = new Map<String, String>(owdCache);
    merged.putAll(owdOverride);
    return merged;
  }

  /** True when rules can change who sees the object (its default is Private or Public Read Only). */
  public static Boolean isRestricted(String objectApi) {
    String owd = sharingDefaults().get(objectApi);
    return owd == 'Private' || owd == 'Read';
  }

  /** The row cause to use, or null when the object has no PMS Access Rule sharing reason yet. */
  public static String rowCauseFor(String objectApi) {
    if (rowCauseOverride != null) {
      return rowCauseOverride;
    }
    Schema.SObjectType shareType = Schema.getGlobalDescribe()
      .get(shareObjectName(objectApi));
    if (shareType == null) {
      return null;
    }
    Schema.SObjectField f = shareType.getDescribe()
      .fields.getMap()
      .get('RowCause');
    if (f == null) {
      return null;
    }
    for (Schema.PicklistEntry p : f.getDescribe().getPicklistValues()) {
      if (p.getValue() == ROW_CAUSE) {
        return ROW_CAUSE;
      }
    }
    return null;
  }

  public static String shareObjectName(String objectApi) {
    return objectApi.removeEnd('__c') + '__Share';
  }

  public static String teamGroupName(Id teamId) {
    return TEAM_GROUP_PREFIX + String.valueOf(teamId).left(15);
  }

  /** Active rules of active teams, with the group each one shares to. */
  public static List<RuleInfo> activeRules() {
    if (ruleCache != null) {
      return ruleCache;
    }
    List<PMS_Access_Rule__c> rules = [
      SELECT
        Id,
        Team__c,
        Team__r.All_Internal_Users__c,
        Site__c,
        Module__c,
        Objects__c,
        Access_Level__c
      FROM PMS_Access_Rule__c
      WHERE Active__c = TRUE AND Team__r.Active__c = TRUE
    ];
    Set<String> groupNames = new Set<String>();
    for (PMS_Access_Rule__c r : rules) {
      groupNames.add(teamGroupName(r.Team__c));
    }
    Map<String, Id> groupIds = new Map<String, Id>();
    for (Group g : [
      SELECT Id, DeveloperName
      FROM Group
      WHERE DeveloperName IN :groupNames OR Type = 'Organization'
    ]) {
      groupIds.put(g.DeveloperName, g.Id);
    }
    Id everyone = groupIds.get('AllInternalUsers');
    ruleCache = new List<RuleInfo>();
    for (PMS_Access_Rule__c r : rules) {
      RuleInfo ri = new RuleInfo();
      ri.ruleId = r.Id;
      ri.teamId = r.Team__c;
      ri.groupId = r.Team__r.All_Internal_Users__c
        ? everyone
        : groupIds.get(teamGroupName(r.Team__c));
      ri.siteId = r.Site__c;
      ri.module = String.isBlank(r.Module__c) ? 'All' : r.Module__c;
      if (String.isNotBlank(r.Objects__c)) {
        ri.keys.addAll(r.Objects__c.split(';'));
      }
      ri.edit = r.Access_Level__c == 'Edit';
      if (ri.groupId != null) {
        ruleCache.add(ri);
      }
    }
    return ruleCache;
  }

  @TestVisible
  static void resetCaches() {
    owdCache = null;
    ruleCache = null;
  }

  // ------------------------------------------------------------------ matching

  /** Does a rule apply to a record of this site / module / kind? */
  public static Boolean matches(
    RuleInfo r,
    Id siteId,
    String module,
    String ruleKey
  ) {
    if (r.siteId != null && r.siteId != siteId) {
      return false;
    }
    if (r.module != 'All' && r.module != module) {
      return false;
    }
    if (!r.keys.isEmpty() && !r.keys.contains(ruleKey)) {
      return false;
    }
    return true;
  }

  /**
   * Group id -> 'Read' or 'Edit' for one record. Edit wins over Read.
   * With a Public Read Only default, Read grants add nothing and are left out.
   */
  @TestVisible
  static Map<Id, String> desiredAccess(
    Id siteId,
    String module,
    String ruleKey,
    List<RuleInfo> rules,
    String owd
  ) {
    Map<Id, String> out = new Map<Id, String>();
    for (RuleInfo r : rules) {
      if (!matches(r, siteId, module, ruleKey)) {
        continue;
      }
      String level = r.edit ? 'Edit' : 'Read';
      if (owd == 'Read' && level == 'Read') {
        continue;
      }
      if (out.get(r.groupId) != 'Edit') {
        out.put(r.groupId, level);
      }
    }
    return out;
  }

  /** First non-blank Id along the comma-separated paths, for example Booking__r.Site__c. */
  public static Id resolvePath(SObject rec, String paths) {
    for (String raw : paths.split(',')) {
      String path = raw.trim();
      if (String.isBlank(path)) {
        continue;
      }
      List<String> parts = path.split('\\.');
      SObject cur = rec;
      for (Integer i = 0; i < parts.size() - 1 && cur != null; i++) {
        cur = cur.getSObject(parts[i]);
      }
      if (cur != null) {
        Object v = cur.get(parts[parts.size() - 1]);
        if (v != null) {
          return (Id) v;
        }
      }
    }
    return null;
  }

  /** Fields on the record itself that, when changed, can move it to another site. */
  public static Set<String> firstHopFields(String paths) {
    Set<String> out = new Set<String>();
    for (String raw : paths.split(',')) {
      String first = raw.trim().split('\\.')[0];
      if (first == 'Id' || String.isBlank(first)) {
        continue;
      }
      out.add(first.endsWith('__r') ? first.removeEnd('__r') + '__c' : first);
    }
    return out;
  }

  public class Resolved {
    public Map<Id, Id> siteByRecord = new Map<Id, Id>();
    public Map<Id, String> moduleBySite = new Map<Id, String>();
  }

  public static Resolved resolve(PMS_Access_Object__mdt cfg, Set<Id> ids) {
    Resolved res = new Resolved();
    List<String> fields = new List<String>{ 'Id' };
    for (String p : cfg.Site_Paths__c.split(',')) {
      String t = p.trim();
      if (String.isNotBlank(t) && t != 'Id' && !fields.contains(t)) {
        fields.add(t);
      }
    }
    String soql =
      'SELECT ' +
      String.join(fields, ', ') +
      ' FROM ' +
      cfg.Object_API_Name__c +
      ' WHERE Id IN :ids';
    for (SObject rec : Database.query(soql)) {
      res.siteByRecord.put(rec.Id, resolvePath(rec, cfg.Site_Paths__c));
    }
    Set<Id> siteIds = new Set<Id>(res.siteByRecord.values());
    siteIds.remove(null);
    for (PMS_Site__c s : [
      SELECT Id, Module__c
      FROM PMS_Site__c
      WHERE Id IN :siteIds
    ]) {
      res.moduleBySite.put(s.Id, s.Module__c);
    }
    return res;
  }

  // ------------------------------------------------------------------ apply

  /** Bring the PMS Access Rule shares of these records in line with the current rules. */
  public static void recalcRecords(String objectApi, Set<Id> ids) {
    if (ids == null || ids.isEmpty()) {
      return;
    }
    PMS_Access_Object__mdt cfg = configFor(objectApi);
    if (cfg == null || !isRestricted(objectApi)) {
      return;
    }
    String rowCause = rowCauseFor(objectApi);
    if (rowCause == null) {
      lastErrors.add(
        objectApi +
        ': the PMS Access Rule sharing reason is missing. Deploy the post-owd folder.'
      );
      return;
    }
    String owd = sharingDefaults().get(objectApi);
    List<RuleInfo> rules = activeRules();
    Resolved res = resolve(cfg, ids);

    Map<Id, Map<Id, String>> desired = new Map<Id, Map<Id, String>>();
    for (Id recId : res.siteByRecord.keySet()) {
      Id siteId = res.siteByRecord.get(recId);
      desired.put(
        recId,
        desiredAccess(
          siteId,
          res.moduleBySite.get(siteId),
          cfg.Rule_Key__c,
          rules,
          owd
        )
      );
    }

    String shareName = shareObjectName(objectApi);
    Set<Id> recIds = res.siteByRecord.keySet();
    List<SObject> existing = Database.query(
      'SELECT Id, ParentId, UserOrGroupId, AccessLevel FROM ' +
        shareName +
        ' WHERE ParentId IN :recIds AND RowCause = :rowCause'
    );
    List<SObject> toDelete = new List<SObject>();
    Map<Id, Map<Id, String>> keep = new Map<Id, Map<Id, String>>();
    for (SObject s : existing) {
      Id parent = (Id) s.get('ParentId');
      Id grantee = (Id) s.get('UserOrGroupId');
      String want = desired.containsKey(parent)
        ? desired.get(parent).get(grantee)
        : null;
      if (want != null && want == (String) s.get('AccessLevel')) {
        if (!keep.containsKey(parent)) {
          keep.put(parent, new Map<Id, String>());
        }
        keep.get(parent).put(grantee, want);
      } else {
        toDelete.add(s);
      }
    }
    Schema.SObjectType shareType = Schema.getGlobalDescribe().get(shareName);
    List<SObject> toInsert = new List<SObject>();
    for (Id parent : desired.keySet()) {
      for (Id grantee : desired.get(parent).keySet()) {
        if (keep.containsKey(parent) && keep.get(parent).containsKey(grantee)) {
          continue;
        }
        SObject s = shareType.newSObject();
        s.put('ParentId', parent);
        s.put('UserOrGroupId', grantee);
        s.put('AccessLevel', desired.get(parent).get(grantee));
        s.put('RowCause', rowCause);
        toInsert.add(s);
      }
    }
    if (!toDelete.isEmpty()) {
      collect(Database.delete(toDelete, false), objectApi + ' delete');
    }
    if (!toInsert.isEmpty()) {
      collect(Database.insert(toInsert, false), objectApi + ' insert');
    }
  }

  static void collect(List<Database.SaveResult> results, String what) {
    for (Database.SaveResult r : results) {
      if (!r.isSuccess()) {
        lastErrors.add(what + ': ' + r.getErrors()[0].getMessage());
      }
    }
  }

  static void collect(List<Database.DeleteResult> results, String what) {
    for (Database.DeleteResult r : results) {
      if (!r.isSuccess()) {
        lastErrors.add(what + ': ' + r.getErrors()[0].getMessage());
      }
    }
  }

  // ------------------------------------------------------------------ triggers

  /**
   * Called from the PMS_AccessShare_* triggers. Never blocks a save: problems are only logged.
   * isAfter is passed in so the single trigger line also runs (and is covered) on before insert.
   */
  public static void handleTrigger(
    String objectApi,
    Boolean isAfter,
    List<SObject> news,
    Map<Id, SObject> olds
  ) {
    if (!isAfter || news == null) {
      return;
    }
    try {
      PMS_Access_Object__mdt cfg = configFor(objectApi);
      if (cfg == null) {
        return;
      }
      if (objectApi == 'PMS_Site__c' && olds != null) {
        for (SObject n : news) {
          if (n.get('Module__c') != olds.get(n.Id).get('Module__c')) {
            queueFullRecalc();
            break;
          }
        }
      }
      if (!isRestricted(objectApi)) {
        return;
      }
      Set<String> watch = firstHopFields(cfg.Site_Paths__c);
      watch.add('OwnerId');
      Map<String, Schema.SObjectField> fieldMap = news[0]
        .getSObjectType()
        .getDescribe()
        .fields.getMap();
      Set<Id> ids = new Set<Id>();
      for (SObject n : news) {
        if (olds == null) {
          ids.add(n.Id);
          continue;
        }
        SObject o = olds.get(n.Id);
        for (String f : watch) {
          if (fieldMap.containsKey(f) && n.get(f) != o.get(f)) {
            ids.add(n.Id);
            break;
          }
        }
      }
      recalcRecords(objectApi, ids);
    } catch (Exception e) {
      lastErrors.add(objectApi + ' trigger: ' + e.getMessage());
      System.debug(LoggingLevel.ERROR, 'PMS access engine: ' + e.getMessage());
    }
  }

  /** Group sync for every team, then a recalculation of every restricted object. Once per transaction. */
  public static void queueFullRecalc() {
    if (fullRecalcQueued) {
      return;
    }
    fullRecalcQueued = true;
    if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
      System.enqueueJob(new PMS_AccessGroupSync(null, true));
    }
  }

  // ------------------------------------------------------------------ explain

  public class Explanation {
    @AuraEnabled
    public String objectLabel;
    @AuraEnabled
    public String sharingDefault;
    @AuraEnabled
    public Boolean restricted;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public String module;
    @AuraEnabled
    public List<String> grantingRules = new List<String>();
    @AuraEnabled
    public List<String> otherMatchingRules = new List<String>();
  }

  /** Which rules apply to a record, and which of them reach this user. */
  public static Explanation explain(Id userId, Id recordId) {
    Explanation ex = new Explanation();
    String objectApi = recordId.getSObjectType().getDescribe().getName();
    ex.objectLabel = recordId.getSObjectType().getDescribe().getLabel();
    ex.sharingDefault = sharingDefaults().get(objectApi);
    ex.restricted = isRestricted(objectApi);
    PMS_Access_Object__mdt cfg = configFor(objectApi);
    if (cfg == null) {
      return ex;
    }
    Resolved res = resolve(cfg, new Set<Id>{ recordId });
    Id siteId = res.siteByRecord.get(recordId);
    ex.module = siteId == null ? null : res.moduleBySite.get(siteId);
    if (siteId != null) {
      ex.siteName = [SELECT Name FROM PMS_Site__c WHERE Id = :siteId].Name;
    }
    Set<Id> myTeams = new Set<Id>();
    for (
      PMS_Access_Team_Member__c m : activeMemberships(new Set<Id>{ userId })
    ) {
      myTeams.add(m.Team__c);
    }
    Map<Id, PMS_Access_Rule__c> details = new Map<Id, PMS_Access_Rule__c>(
      [
        SELECT
          Id,
          Name,
          Team__r.Name,
          Team__r.All_Internal_Users__c,
          Access_Level__c
        FROM PMS_Access_Rule__c
        WHERE Active__c = TRUE
      ]
    );
    for (RuleInfo r : activeRules()) {
      if (!matches(r, siteId, ex.module, cfg.Rule_Key__c)) {
        continue;
      }
      PMS_Access_Rule__c d = details.get(r.ruleId);
      String text =
        d.Name +
        ' (' +
        d.Team__r.Name +
        ', ' +
        d.Access_Level__c +
        ')';
      if (d.Team__r.All_Internal_Users__c || myTeams.contains(r.teamId)) {
        ex.grantingRules.add(text);
      } else {
        ex.otherMatchingRules.add(text);
      }
    }
    return ex;
  }

  /** Memberships that count today: member and team active, user active, inside the date range. */
  public static List<PMS_Access_Team_Member__c> activeMemberships(
    Set<Id> userIds
  ) {
    Date today = Date.today();
    String soql =
      'SELECT Id, Team__c, User__c, Team__r.Hide_Amounts__c, Team__r.Hide_Customer_Details__c, Team__r.All_Internal_Users__c ' +
      'FROM PMS_Access_Team_Member__c WHERE Active__c = TRUE AND Team__r.Active__c = TRUE AND User__c != NULL ' +
      'AND User__r.IsActive = TRUE AND User__r.UserType = \'Standard\' AND (Start_Date__c = NULL OR Start_Date__c <= :today) AND (End_Date__c = NULL OR End_Date__c >= :today)';
    if (userIds != null) {
      soql += ' AND User__c IN :userIds';
    }
    return Database.query(soql);
  }
}
