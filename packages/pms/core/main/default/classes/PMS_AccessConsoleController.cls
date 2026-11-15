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
  }

  @AuraEnabled
  public static Overview getOverview() {
    try {
      Overview o = new Overview();
      o.canManage = FeatureManagement.checkPermission('PMS_Manage_Access');
      Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
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
