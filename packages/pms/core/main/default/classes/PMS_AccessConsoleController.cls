/**
 * Back end of the Access Setup console (LWC pmsAccessConsole).
 * Reading is open to anyone with access to the page; changing anything needs PMS_Manage_Access.
 */
public with sharing class PMS_AccessConsoleController {
  public class ObjectRow {
    @AuraEnabled
    public String objectApi;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String ruleKey;
    @AuraEnabled
    public String sharingDefault;
    @AuraEnabled
    public Boolean restricted;
    @AuraEnabled
    public Boolean reasonReady;
    @AuraEnabled
    public String rolloutTarget;
    @AuraEnabled
    public String rolloutStep;
    @AuraEnabled
    public String rolloutMessage;
    @AuraEnabled
    public Boolean rolloutActive = false;
  }

  public class JobRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer processed;
    @AuraEnabled
    public Integer total;
    @AuraEnabled
    public Integer errors;
    @AuraEnabled
    public Datetime created;
    @AuraEnabled
    public Datetime completed;
  }

  public class Overview {
    @AuraEnabled
    public Boolean canManage;
    @AuraEnabled
    public List<ObjectRow> objects = new List<ObjectRow>();
    @AuraEnabled
    public List<PMS_Access_Team__c> teams;
    @AuraEnabled
    public List<PMS_Access_Rule__c> rules;
    @AuraEnabled
    public List<JobRow> jobs = new List<JobRow>();
    @AuraEnabled
    public Boolean nightlyScheduled;
    @AuraEnabled
    public Boolean rolloutActive = false;
  }

  @AuraEnabled
  public static Overview getOverview() {
    try {
      Overview o = new Overview();
      o.canManage = FeatureManagement.checkPermission('PMS_Manage_Access');
      Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
      Map<String, PMS_Access_Rollout__c> rollout = PMS_AccessRollout.allRows();
      for (PMS_Access_Object__mdt c : PMS_AccessService.objectConfigs()) {
        ObjectRow r = new ObjectRow();
        r.objectApi = c.Object_API_Name__c;
        Schema.SObjectType t = gd.get(c.Object_API_Name__c);
        r.label = t == null
          ? c.Object_API_Name__c
          : t.getDescribe().getLabelPlural();
        r.ruleKey = c.Rule_Key__c;
        r.sharingDefault = PMS_AccessService.sharingDefaults()
          .get(c.Object_API_Name__c);
        r.restricted = PMS_AccessService.isRestricted(c.Object_API_Name__c);
        r.reasonReady =
          PMS_AccessService.rowCauseFor(c.Object_API_Name__c) != null;
        PMS_Access_Rollout__c ro = rollout.get(c.Object_API_Name__c);
        if (ro != null) {
          r.rolloutTarget = ro.Target__c;
          r.rolloutStep = ro.Step__c;
          r.rolloutMessage = ro.Message__c;
          r.rolloutActive = !PMS_AccessRollout.FINAL_STEPS.contains(ro.Step__c);
          o.rolloutActive = o.rolloutActive || r.rolloutActive;
        }
        o.objects.add(r);
      }
      o.teams = [
        SELECT
          Id,
          Name,
          Active__c,
          All_Internal_Users__c,
          Hide_Amounts__c,
          Hide_Customer_Details__c,
          Member_Count__c,
          Description__c
        FROM PMS_Access_Team__c
        WITH USER_MODE
        ORDER BY Name
        LIMIT 500
      ];
      o.rules = [
        SELECT
          Id,
          Name,
          Team__c,
          Team__r.Name,
          Site__c,
          Site__r.Name,
          Module__c,
          Objects__c,
          Access_Level__c,
          Active__c,
          Description__c
        FROM PMS_Access_Rule__c
        WITH USER_MODE
        ORDER BY Team__r.Name, Name
        LIMIT 2000
      ];
      o.jobs = recentJobs();
      o.nightlyScheduled = ![
          SELECT Id
          FROM CronTrigger
          WHERE CronJobDetail.Name LIKE 'PMS Access%'
          LIMIT 1
        ]
        .isEmpty();
      return o;
    } catch (Exception e) {
      if (Test.isRunningTest()) {
        throw e;
      }
      throw new AuraHandledException(e.getMessage());
    }
  }

  static List<JobRow> recentJobs() {
    List<JobRow> out = new List<JobRow>();
    for (AsyncApexJob j : [
      SELECT
        Id,
        ApexClass.Name,
        Status,
        JobItemsProcessed,
        TotalJobItems,
        NumberOfErrors,
        CreatedDate,
        CompletedDate
      FROM AsyncApexJob
      WHERE
        ApexClass.Name IN ('PMS_AccessGroupSync', 'PMS_AccessRecalcBatch')
        AND JobType IN ('Queueable', 'BatchApex')
      ORDER BY CreatedDate DESC
      LIMIT 10
    ]) {
      JobRow r = new JobRow();
      r.id = j.Id;
      r.className = j.ApexClass.Name == 'PMS_AccessGroupSync'
        ? 'Team sync'
        : 'Share recalculation';
      r.status = j.Status;
      r.processed = j.JobItemsProcessed;
      r.total = j.TotalJobItems;
      r.errors = j.NumberOfErrors;
      r.created = j.CreatedDate;
      r.completed = j.CompletedDate;
      out.add(r);
    }
    return out;
  }

  @AuraEnabled
  public static Id recalculateNow() {
    requireManage();
    return System.enqueueJob(new PMS_AccessGroupSync(null, true));
  }

  @AuraEnabled
  public static String scheduleNightly() {
    requireManage();
    if (
      ![
          SELECT Id
          FROM CronTrigger
          WHERE CronJobDetail.Name LIKE 'PMS Access%'
          LIMIT 1
        ]
        .isEmpty()
    ) {
      return 'already';
    }
    System.schedule(
      'PMS Access Nightly',
      '0 30 1 * * ?',
      new PMS_AccessNightly()
    );
    return 'scheduled';
  }

  // ------------------------------------------------------------------ bulk sharing defaults

  /**
   * Starts moving the selected objects to a new sharing default.
   *   mode 'apply'  : guided Apply rules (ends Private, adds the sharing reason and recalculates on the way)
   *   mode 'set'    : plain change to target Read, ReadWrite or Private. Private is only allowed for objects
   *                   already under rules (Public Read Only with the sharing reason); use Apply rules otherwise.
   * Returns how many objects were queued.
   */
  @AuraEnabled
  public static Integer startRollout(
    List<String> objectApis,
    String mode,
    String target
  ) {
    requireManage();
    try {
      if (objectApis == null || objectApis.isEmpty()) {
        throw new AuraHandledException('Select at least one kind of record.');
      }
      String finalTarget = mode == 'apply' ? 'Private' : target;
      if (
        finalTarget != 'Private' &&
        finalTarget != 'Read' &&
        finalTarget != 'ReadWrite'
      ) {
        throw new AuraHandledException('Choose a sharing default.');
      }
      Set<String> configured = new Set<String>();
      for (PMS_Access_Object__mdt c : PMS_AccessService.objectConfigs()) {
        configured.add(c.Object_API_Name__c);
      }
      Map<String, String> owd = PMS_AccessService.sharingDefaults();
      Map<String, PMS_Access_Rollout__c> existing = PMS_AccessRollout.allRows();
      List<String> notReady = new List<String>();
      List<String> busy = new List<String>();
      for (String o : objectApis) {
        if (!configured.contains(o)) {
          throw new AuraHandledException(
            o + ' isn\'t one of the objects under access rules.'
          );
        }
        PMS_Access_Rollout__c ex = existing.get(o);
        if (
          ex != null &&
          !PMS_AccessRollout.FINAL_STEPS.contains(ex.Step__c) &&
          ex.Target__c != finalTarget
        ) {
          busy.add(label(o));
        }
        if (mode != 'apply' && finalTarget == 'Private') {
          String cur = owd.get(o);
          if (
            !((cur == 'Read' || cur == 'Private') &&
            PMS_AccessService.rowCauseFor(o) != null)
          ) {
            notReady.add(label(o));
          }
        }
      }
      if (!busy.isEmpty()) {
        throw new AuraHandledException(
          'Already changing: ' +
            String.join(busy, ', ') +
            '. Stop those first or wait until they finish.'
        );
      }
      if (!notReady.isEmpty()) {
        throw new AuraHandledException(
          'Private would cut staff off from these records, because rules aren\'t applied to them yet: ' +
            String.join(notReady, ', ') +
            '. Use Apply rules instead.'
        );
      }

      // Prove the Metadata API connection before queuing anything (a callout has to come before any save).
      PMS_AccessMetadataClient.ping();

      List<PMS_Access_Rollout__c> rows = new List<PMS_Access_Rollout__c>();
      for (String o : objectApis) {
        PMS_Access_Rollout__c r = existing.containsKey(o)
          ? existing.get(o)
          : new PMS_Access_Rollout__c(Name = o);
        Boolean keepProgress =
          !PMS_AccessRollout.FINAL_STEPS.contains(r.Step__c) &&
          r.Target__c == finalTarget &&
          r.Id != null;
        if (!keepProgress) {
          r.Target__c = finalTarget;
          r.Step__c = PMS_AccessRollout.STEP_WAITING;
          r.Message__c = null;
          r.Requested__c = null;
          r.Requested_At__c = null;
          r.Recalc_Started__c = false;
          r.Attempts__c = 0;
          r.Ticks__c = 0;
        }
        rows.add(r);
      }
      upsert rows;
      PMS_AccessRollout.ensureRunning();
      return rows.size();
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /** Stops changes that haven't finished. A step already sent to Salesforce still completes. */
  @AuraEnabled
  public static Integer cancelRollout(List<String> objectApis) {
    requireManage();
    List<PMS_Access_Rollout__c> rows = new List<PMS_Access_Rollout__c>();
    Set<String> only = objectApis == null || objectApis.isEmpty()
      ? null
      : new Set<String>(objectApis);
    for (PMS_Access_Rollout__c r : PMS_AccessRollout.activeRows()) {
      if (only == null || only.contains(r.Name)) {
        r.Step__c = PMS_AccessRollout.STEP_CANCELLED;
        r.Message__c = 'Stopped by ' + UserInfo.getName() + '.';
        rows.add(r);
      }
    }
    update rows;
    return rows.size();
  }

  static String label(String objectApi) {
    Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApi);
    return t == null ? objectApi : t.getDescribe().getLabelPlural();
  }

  // ------------------------------------------------------------------ check access

  public class AccessCheck {
    @AuraEnabled
    public String userName;
    @AuraEnabled
    public String recordName;
    @AuraEnabled
    public Boolean hasRead;
    @AuraEnabled
    public Boolean hasEdit;
    @AuraEnabled
    public Boolean viewAllData;
    @AuraEnabled
    public PMS_AccessService.Explanation explanation;
  }

  /** Can this user see / edit this record, and which rules explain it? */
  @AuraEnabled
  public static AccessCheck checkAccess(Id userId, String recordIdOrUrl) {
    requireManage();
    try {
      Id recordId = parseId(recordIdOrUrl);
      AccessCheck c = new AccessCheck();
      User u = [
        SELECT Name, Profile.PermissionsViewAllData
        FROM User
        WHERE Id = :userId
      ];
      c.userName = u.Name;
      c.viewAllData = u.Profile.PermissionsViewAllData;
      UserRecordAccess a = [
        SELECT RecordId, HasReadAccess, HasEditAccess
        FROM UserRecordAccess
        WHERE UserId = :userId AND RecordId = :recordId
      ];
      c.hasRead = a.HasReadAccess;
      c.hasEdit = a.HasEditAccess;
      String objectApi = recordId.getSObjectType().getDescribe().getName();
      List<SObject> rec = Database.query(
        'SELECT Name FROM ' + objectApi + ' WHERE Id = :recordId'
      );
      c.recordName = rec.isEmpty()
        ? String.valueOf(recordId)
        : (String) rec[0].get('Name');
      c.explanation = PMS_AccessService.explain(userId, recordId);
      return c;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @TestVisible
  static Id parseId(String s) {
    if (String.isBlank(s)) {
      throw new AuraHandledException('Paste a record Id or the record\'s URL.');
    }
    Matcher m = Pattern.compile('([a-zA-Z0-9]{15}|[a-zA-Z0-9]{18})')
      .matcher(s.trim());
    String candidate = null;
    while (m.find()) {
      String t = m.group(1);
      if (t.length() == 18 || t.length() == 15) {
        try {
          Id parsed = Id.valueOf(t);
          candidate = t;
        } catch (Exception ignore) {
          continue;
        }
      }
    }
    if (candidate == null) {
      throw new AuraHandledException(
        'That doesn\'t look like a record Id or link.'
      );
    }
    return Id.valueOf(candidate);
  }

  static void requireManage() {
    if (!FeatureManagement.checkPermission('PMS_Manage_Access')) {
      throw new AuraHandledException(
        'You need the PMS Access Manager permission set.'
      );
    }
  }
}
