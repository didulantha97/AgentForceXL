/**
 * Demo and test data loader for the PMS (Core).
 *
 *   PMS_DemoData.load('baseline')   fills every module so every home KPI and attention list has something to show
 *   PMS_DemoData.load('busy-weekend' | 'overdue-wave' | 'month-end' | 'channel-incident' | 'new-client')
 *   PMS_DemoData.reset('overdue-wave' | 'baseline' | 'all')
 *   PMS_DemoData.status()
 *
 * Safety:
 *  - Refuses to run in production. Sandboxes and scratch orgs are allowed; Developer Edition and trial orgs only
 *    after an opt-in (PMS_Settings__c.Demo_Data_Allowed__c, set by scripts/pms-package.sh for orgs it vetted).
 *  - Admin only: PMS Manage Demo Data custom permission, or Modify All Data.
 *  - Refuses while the licence is suspended and checks the room / unit / booking caps first.
 *  - DML and SOQL run in user mode, so the admin's CRUD and field security apply.
 *
 * How it works:
 *  - A pack is a list of steps (one per module). Each step runs in its own Queueable transaction, chained one
 *    after the other, so the triggers, sharing and licence checks that normally run on insert never hit the
 *    governor limits together. A step is atomic: it rolls back to a savepoint on any error and records the
 *    reason, so a pack is either missing, loading, loaded, or failed (reset it, then load again).
 *  - Everything created is tracked in PMS_Demo_Record__c (Pack, Record Id, Object, Sequence). Reset deletes the
 *    tracked records from the highest sequence down, so children go before parents (several lookups restrict
 *    deletion), then the tracking rows. Records created by triggers (room nights, inventory days) go with their
 *    parents. Nothing is added to other objects.
 *  - load() is idempotent: a pack that already has tracking rows is not loaded again.
 *  - Dates are relative to today. Currency is SEK, names and addresses are Swedish.
 *  - Real triggers run on every insert (double-booking check, room nights, inventory, invoice totals). Past-dated
 *    stays are accepted by those triggers, so PMS_BookingTriggerHandler.bypass is never used. The Experience
 *    guarantee triggers are switched off with PMS_TriggerBypass.policyFees so no card links or fees are queued.
 *
 * Side effects of the real scheduled jobs on demo data:
 *  - Prevented: dunning (every demo invoice is Dunning_Paused__c with reason "Demo data", the hand-made reminder
 *    history stays); guarantee job card-link e-mails and check-in invitations (demo bookings are stamped as already
 *    mailed, see Ctx.add).
 *  - Remaining, accepted: the nightly rent run, night audit, owner statement refresh and rent adjustment job still treat
 *    demo leases, in-house stays and sites like real ones, so they can add charges, invoices or statements that are not
 *    tracked (Reset then reports STUCK for a parent it cannot delete; remove those by hand). Dynamic pricing (N4)
 *    drifts demo rates, which is harmless. Reset keeps demo accounts / sites that gained records of their own.
 */
public with sharing class PMS_DemoData {
  public class DemoException extends Exception {
  }

  public static final String BASELINE = 'baseline';
  public static final String ALL = 'all';
  public static final Integer ROOMS = 12;
  public static final Integer UNITS = 8;

  @TestVisible
  private static final String MARKER = 'marker';
  private static final String START_MARK = 'START:';
  private static final String DONE_MARK = 'DONE:';
  private static final String ERR_MARK = 'ERR:';
  private static final String RESET_MARK = 'RESET:';
  private static final Integer STALE_MINUTES = 60;
  private static final Integer ASSUMED_MAX_DEPTH = 5;

  public static final String NONE = 'NONE';
  public static final String RUNNING = 'RUNNING';
  public static final String DONE = 'DONE';
  public static final String FAILED = 'FAILED';
  public static final String RESETTING = 'RESETTING';

  // Test hooks
  @TestVisible
  private static String envOverride; // 'allow' (sandbox/scratch), 'optin' (Developer Edition/trial) or 'deny'
  @TestVisible
  private static Boolean adminOverride;
  @TestVisible
  private static String failAt; // step name that throws, to exercise the failure path

  // ------------------------------------------------------------------ pack catalogue

  public class PackDef {
    public String key;
    public String label;
    public String description;
    public List<String> steps;
    public Boolean needsBaseline;
    PackDef(
      String key,
      String label,
      String description,
      List<String> steps,
      Boolean needsBaseline
    ) {
      this.key = key;
      this.label = label;
      this.description = description;
      this.steps = steps;
      this.needsBaseline = needsBaseline;
    }
  }

  private static final List<PackDef> CATALOG = new List<PackDef>{
    new PackDef(
      BASELINE,
      'Baseline',
      'Every module: a hotel, a rental building, projects and a clinic with bookings, leases, appointments, invoices, payments, work orders, channel logs and requests. Every home KPI and attention list shows data.',
      new List<String>{
        'core',
        'hotel',
        'property',
        'projects',
        'practice',
        'billing',
        'service',
        'ops',
        'channels'
      },
      false
    ),
    new PackDef(
      'busy-weekend',
      'Busy weekend',
      'About 14 extra hotel bookings over the next three days, for occupancy and housekeeping demos.',
      new List<String>{ 'busy' },
      true
    ),
    new PackDef(
      'overdue-wave',
      'Overdue wave',
      '12 overdue invoices aged 10 to 120 days with reminder history and two payment plans.',
      new List<String>{ 'wave' },
      true
    ),
    new PackDef(
      'month-end',
      'Month end',
      'A hotel owner statement to publish, vendor bills falling due and rent reviews to approve.',
      new List<String>{ 'month' },
      true
    ),
    new PackDef(
      'channel-incident',
      'Channel incident',
      'Six channel manager errors in the last 24 hours.',
      new List<String>{ 'incident' },
      true
    ),
    new PackDef(
      'new-client',
      'New client',
      'A fresh practice client with matters in intake and a new project to plan.',
      new List<String>{ 'newclient' },
      true
    )
  };

  private static PackDef def(String key) {
    for (PackDef d : CATALOG) {
      if (d.key == key) {
        return d;
      }
    }
    return null;
  }

  private static String normalise(String pack) {
    return pack == null ? '' : pack.trim().toLowerCase();
  }

  // ------------------------------------------------------------------ status DTOs

  public class PackInfo {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String description;
    /** NONE, RUNNING, DONE, FAILED or RESETTING */
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer records = 0;
    @AuraEnabled
    public Boolean needsBaseline = false;
  }

  public class CountRow {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Integer count;
  }

  public class Status {
    /** False hides the whole card: production, or the user is not an admin. */
    @AuraEnabled
    public Boolean allowed = false;
    /** False while the licence is suspended: the card shows but nothing can be started. */
    @AuraEnabled
    public Boolean canRun = false;
    /** True while any pack is loading or being removed. */
    @AuraEnabled
    public Boolean busy = false;
    /** True for an admin in a Developer Edition / trial org that has not opted in: the card shows the reason. */
    @AuraEnabled
    public Boolean optInRequired = false;
    @AuraEnabled
    public String reason;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer total = 0;
    @AuraEnabled
    public List<PackInfo> packs = new List<PackInfo>();
    @AuraEnabled
    public List<CountRow> counts = new List<CountRow>();
  }

  // ------------------------------------------------------------------ guards

  public static final String OPT_IN_MESSAGE = 'This is a Developer Edition or trial org, so demo data is switched off until you opt in: tick "Demo Data Allowed" on the org-level PMS Settings record (Setup > Custom Settings > PMS Settings > Manage), or run scripts/pms-package.sh demo-data for this org.';

  /** production (refused), open (sandbox or scratch org: allowed) or optin (Developer Edition / trial: needs the setting). */
  private static String orgKind() {
    if (envOverride != null) {
      return envOverride == 'allow'
        ? 'open'
        : (envOverride == 'optin' ? 'optin' : 'production');
    }
    Organization o = [
      SELECT IsSandbox, OrganizationType, TrialExpirationDate
      FROM Organization
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    String host = '';
    try {
      host = URL.getOrgDomainUrl().getHost();
    } catch (Exception e) {
      host = '';
    }
    if (o.IsSandbox == true || host.contains('.scratch.')) {
      return 'open';
    }
    Boolean trialOrDev =
      o.TrialExpirationDate != null ||
      (o.OrganizationType != null && o.OrganizationType.contains('Developer'));
    return trialOrDev ? 'optin' : 'production';
  }

  /** Null unless the org is production-like (never allowed). */
  public static String environmentProblem() {
    return orgKind() == 'production'
      ? 'Demo data can only be loaded in a sandbox, scratch, trial or Developer Edition org, never in production.'
      : null;
  }

  /** Null unless this is a Developer Edition / trial org where nobody has opted in yet. */
  public static String optInProblem() {
    if (orgKind() != 'optin') {
      return null;
    }
    Boolean enabled = optInOverride != null
      ? optInOverride
      : PMS_Settings__c.getOrgDefaults().Demo_Data_Allowed__c == true;
    return enabled ? null : OPT_IN_MESSAGE;
  }

  @TestVisible
  private static Boolean optInOverride;

  public static Boolean isAdmin() {
    if (adminOverride != null) {
      return adminOverride;
    }
    if (FeatureManagement.checkPermission('PMS_Manage_Demo_Data')) {
      return true;
    }
    // The running user's own permission set assignments only: no data is exposed, so system mode is fine.
    return [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND PermissionSet.PermissionsModifyAllData = TRUE
        WITH SYSTEM_MODE
      ] > 0;
  }

  /** Null when the running user may manage demo data here; otherwise the reason. */
  public static String blockReason() {
    String env = environmentProblem();
    if (env != null) {
      return env;
    }
    if (!isAdmin()) {
      return 'Only PMS administrators can manage demo data (PMS Manage Demo Data permission or Modify All Data).';
    }
    String optIn = optInProblem();
    if (optIn != null) {
      return optIn;
    }
    if (!Schema.sObjectType.PMS_Demo_Record__c.isCreateable()) {
      return 'You need create access to the Demo Record object. Assign the PMS Core Admin permission set.';
    }
    return null;
  }

  /** Null unless the licence is suspended (PMS is read-only then, so nothing can be created). */
  public static String licenceProblem() {
    return PMS_Entitlements.isLocked()
      ? PMS_Entitlements.lockedMessage()
      : null;
  }

  /** Checks the room, unit and booking caps for what the plan is about to create. Null when fine. */
  private static String capProblem(List<String> plan) {
    Integer roomCount = 0;
    Integer unitCount = 0;
    Integer bookingCount = 0;
    for (String item : plan) {
      String step = item.substringAfter(':');
      if (step == 'hotel') {
        roomCount += ROOMS;
        bookingCount += 30;
      } else if (step == 'property') {
        unitCount += UNITS;
        bookingCount += 8;
      } else if (step == 'practice') {
        bookingCount += 30;
      } else if (step == 'busy') {
        bookingCount += 16;
      } else if (step == 'newclient') {
        bookingCount += 4;
      }
    }
    try {
      PMS_Entitlements.assertCanCreate('Room', roomCount);
      PMS_Entitlements.assertCanCreate('Unit', unitCount);
      PMS_Entitlements.assertCanCreate('Booking', bookingCount);
    } catch (PMS_Entitlements.LicenceException e) {
      return e.getMessage();
    }
    return null;
  }

  // ------------------------------------------------------------------ snapshot of what exists

  private class Snapshot {
    Map<String, Integer> records = new Map<String, Integer>();
    Map<String, Map<String, Integer>> byObject = new Map<String, Map<String, Integer>>();
    Set<String> startedPacks = new Set<String>();
    Set<String> donePacks = new Set<String>();
    Set<String> resettingPacks = new Set<String>();
    Map<String, String> errors = new Map<String, String>();
    Map<String, Datetime> startedAt = new Map<String, Datetime>();

    String stateOf(String pack) {
      Integer n = records.containsKey(pack) ? records.get(pack) : 0;
      if (resettingPacks.contains(pack)) {
        return RESETTING;
      }
      if (errors.containsKey(pack)) {
        return FAILED;
      }
      PackDef pd = def(pack);
      if (pd != null && pd.needsBaseline && errors.containsKey(BASELINE)) {
        return FAILED; // built on a baseline that failed: it can never finish
      }
      if (donePacks.contains(pack)) {
        return DONE;
      }
      if (startedPacks.contains(pack)) {
        Datetime t = startedAt.get(pack);
        if (t != null && t < System.now().addMinutes(-STALE_MINUTES)) {
          return FAILED;
        }
        return RUNNING;
      }
      return n > 0 ? FAILED : NONE;
    }

    String messageOf(String pack) {
      String st = stateOf(pack);
      if (st == FAILED && errors.containsKey(pack)) {
        return errors.get(pack);
      }
      if (st == FAILED && errors.containsKey(BASELINE)) {
        return 'The baseline pack failed: ' + errors.get(BASELINE);
      }
      if (st == FAILED) {
        return 'The load did not finish. Reset the pack, then load it again.';
      }
      if (st == RESETTING) {
        return 'Removing records. Reset again if this does not finish.';
      }
      return null;
    }

    Boolean anyBusy() {
      for (PackDef d : CATALOG) {
        String st = stateOf(d.key);
        if (st == RUNNING || st == RESETTING) {
          return true;
        }
      }
      return false;
    }
  }

  private static Snapshot snapshot() {
    Snapshot s = new Snapshot();
    for (AggregateResult ar : [
      SELECT Pack__c p, Object_Name__c o, COUNT(Id) n
      FROM PMS_Demo_Record__c
      WITH USER_MODE
      GROUP BY Pack__c, Object_Name__c
    ]) {
      String pack = (String) ar.get('p');
      String obj = (String) ar.get('o');
      Integer n = (Integer) ar.get('n');
      if (obj == MARKER) {
        continue;
      }
      s.records.put(
        pack,
        (s.records.containsKey(pack) ? s.records.get(pack) : 0) + n
      );
      if (!s.byObject.containsKey(pack)) {
        s.byObject.put(pack, new Map<String, Integer>());
      }
      s.byObject.get(pack).put(obj, n);
    }
    for (PMS_Demo_Record__c m : [
      SELECT Pack__c, Record_Id__c, Name, CreatedDate
      FROM PMS_Demo_Record__c
      WHERE Object_Name__c = :MARKER
      WITH USER_MODE
    ]) {
      String rid = m.Record_Id__c;
      if (rid.startsWith(START_MARK)) {
        s.startedPacks.add(m.Pack__c);
        s.startedAt.put(m.Pack__c, m.CreatedDate);
      } else if (rid.startsWith(DONE_MARK)) {
        s.donePacks.add(m.Pack__c);
      } else if (rid.startsWith(RESET_MARK)) {
        s.resettingPacks.add(m.Pack__c);
      } else if (rid.startsWith(ERR_MARK)) {
        s.errors.put(m.Pack__c, m.Name);
      }
    }
    return s;
  }

  // ------------------------------------------------------------------ public API

  /**
   * The only objects the demo data creates (un-namespaced). Reset refuses to delete anything else, whatever a tracking
   * row says, and status() describes just these instead of the whole org.
   */
  private static final List<String> DEMO_OBJECTS = new List<String>{
    'Account',
    'Contact',
    'Case',
    'PMS_Application__c',
    'PMS_Approval_Request__c',
    'PMS_Booking__c',
    'PMS_Budget_Line__c',
    'PMS_Channel_Log__c',
    'PMS_Channel_Mapping__c',
    'PMS_Charge__c',
    'PMS_Check_In__c',
    'PMS_Document_Request__c',
    'PMS_Dunning_Event__c',
    'PMS_Dunning_Policy__c',
    'PMS_Group_Block__c',
    'PMS_Index_Value__c',
    'PMS_Inspection__c',
    'PMS_Inspection_Item__c',
    'PMS_Intake_Form__c',
    'PMS_Invoice__c',
    'PMS_Lease_Charge_Schedule__c',
    'PMS_Listing__c',
    'PMS_Matter__c',
    'PMS_Meter__c',
    'PMS_Meter_Reading__c',
    'PMS_Milestone__c',
    'PMS_Owner_Statement__c',
    'PMS_Payment__c',
    'PMS_Payment_Plan__c',
    'PMS_Payment_Plan_Instalment__c',
    'PMS_Payment_Policy__c',
    'PMS_Practitioner__c',
    'PMS_Pricing_Factor__c',
    'PMS_Pricing_Strategy__c',
    'PMS_Project__c',
    'PMS_Project_Task__c',
    'PMS_RAID_Item__c',
    'PMS_Rate__c',
    'PMS_Rate_Plan__c',
    'PMS_Rent_Adjustment__c',
    'PMS_Resource__c',
    'PMS_Service__c',
    'PMS_Site__c',
    'PMS_Space__c',
    'PMS_Space_Type__c',
    'PMS_Time_Entry__c',
    'PMS_Vendor_Bill__c',
    'PMS_Vendor_Quote__c',
    'PMS_Work_Order__c'
  };

  /** Namespace prefix of this package in the running org ('' or 'ns__'). */
  private static String prefix() {
    return PMS_Demo_Record__c.SObjectType.getDescribe()
      .getName()
      .substringBefore('PMS_Demo_Record__c');
  }

  /** API names (as the org knows them) of the demo objects. */
  private static Set<String> allowedObjects() {
    Set<String> names = new Set<String>();
    String pre = prefix();
    for (String n : DEMO_OBJECTS) {
      names.add(n.startsWith('PMS_') ? pre + n : n);
    }
    return names;
  }

  private static Map<String, String> labelCache;

  /** Plural label per demo object, described once per transaction for just the allow-list. */
  private static Map<String, String> objectLabels() {
    if (labelCache == null) {
      labelCache = new Map<String, String>();
      List<String> names = new List<String>(allowedObjects());
      for (Schema.DescribeSObjectResult r : Schema.describeSObjects(names)) {
        labelCache.put(r.getName(), r.getLabelPlural());
      }
    }
    return labelCache;
  }

  /** What is loaded, what is running, and whether the running user may manage demo data. */
  public static Status status() {
    Status st = new Status();
    String problem = blockReason();
    if (problem != null) {
      st.reason = problem;
      st.optInRequired = problem == OPT_IN_MESSAGE;
      return st;
    }
    st.allowed = true;
    String lic = licenceProblem();
    st.canRun = lic == null;
    if (lic != null) {
      st.reason = lic;
    }
    Snapshot snap = snapshot();
    st.busy = snap.anyBusy();
    Map<String, Integer> byLabel = new Map<String, Integer>();
    Map<String, String> labelOf = objectLabels();
    for (PackDef d : CATALOG) {
      PackInfo p = new PackInfo();
      p.key = d.key;
      p.label = d.label;
      p.description = d.description;
      p.needsBaseline = d.needsBaseline;
      p.state = snap.stateOf(d.key);
      p.message = snap.messageOf(d.key);
      p.records = snap.records.containsKey(d.key) ? snap.records.get(d.key) : 0;
      st.total += p.records;
      st.packs.add(p);
      Map<String, Integer> objs = snap.byObject.get(d.key);
      if (objs != null) {
        for (String obj : objs.keySet()) {
          String label = labelOf.containsKey(obj) ? labelOf.get(obj) : obj;
          byLabel.put(
            label,
            (byLabel.containsKey(label) ? byLabel.get(label) : 0) +
            objs.get(obj)
          );
        }
      }
    }
    List<String> labels = new List<String>(byLabel.keySet());
    labels.sort();
    for (String l : labels) {
      CountRow r = new CountRow();
      r.label = l;
      r.count = byLabel.get(l);
      st.counts.add(r);
    }
    return st;
  }

  /** Starts loading a pack in the background. Returns a message for the user. */
  public static String load(String pack) {
    String key = normalise(pack);
    PackDef d = def(key);
    if (d == null) {
      List<String> keys = new List<String>();
      for (PackDef x : CATALOG) {
        keys.add(x.key);
      }
      return 'Unknown pack "' +
        pack +
        '". Available packs: ' +
        String.join(keys, ', ') +
        '.';
    }
    String problem = blockReason();
    if (problem != null) {
      return 'Refused: ' + problem;
    }
    problem = licenceProblem();
    if (problem != null) {
      return 'Refused: ' + problem;
    }
    Snapshot snap = snapshot();
    String st = snap.stateOf(key);
    if (st == DONE) {
      return 'Pack "' +
        key +
        '" is already loaded (' +
        snap.records.get(key) +
        ' records). Nothing was added. Reset it first to load it again.';
    }
    if (st == RUNNING) {
      return 'Pack "' +
        key +
        '" is still loading. Check the status in a minute.';
    }
    if (st == RESETTING) {
      return 'Pack "' +
        key +
        '" is being removed. Try again when that has finished.';
    }
    if (st == FAILED) {
      return 'Pack "' +
        key +
        '" did not load completely: ' +
        (snap.messageOf(key) == null ? 'unknown error' : snap.messageOf(key)) +
        ' Reset it, then load it again.';
    }
    List<String> plan = new List<String>();
    List<String> packsToStart = new List<String>();
    String note = '';
    if (d.needsBaseline) {
      String b = snap.stateOf(BASELINE);
      if (b == NONE) {
        for (String step : def(BASELINE).steps) {
          plan.add(BASELINE + ':' + step);
        }
        packsToStart.add(BASELINE);
        note = ' The baseline pack is loaded first because it was missing.';
      } else if (b != DONE) {
        return 'The baseline pack is ' +
          b.toLowerCase() +
          '. Wait for it to finish, or reset it, before loading "' +
          key +
          '".';
      }
    }
    for (String step : d.steps) {
      plan.add(key + ':' + step);
    }
    packsToStart.add(key);
    String cap = capProblem(plan);
    if (cap != null) {
      return 'Refused: ' + cap;
    }
    List<PMS_Demo_Record__c> marks = new List<PMS_Demo_Record__c>();
    for (String p : packsToStart) {
      marks.add(markerRow(p, START_MARK, 'Started ' + System.now().format()));
    }
    try {
      insert as user marks;
    } catch (Exception e) {
      return 'Another load of this pack is already running, or demo records cannot be written: ' +
        e.getMessage();
    }
    enqueue(plan);
    return 'Loading "' +
      key +
      '" in the background (' +
      plan.size() +
      ' steps).' +
      note +
      ' Refresh the status to follow it.';
  }

  /** Removes a pack (or everything with "all") in the background. Resetting the baseline removes all packs. */
  public static String reset(String pack) {
    String key = normalise(pack);
    Boolean everything = key == ALL || key == BASELINE;
    if (!everything && def(key) == null) {
      return 'Unknown pack "' + pack + '". Use a pack name or "all".';
    }
    String problem = blockReason();
    if (problem != null) {
      return 'Refused: ' + problem;
    }
    problem = licenceProblem();
    if (problem != null) {
      return 'Refused: ' + problem;
    }
    Snapshot snap = snapshot();
    List<String> scope = new List<String>();
    for (PackDef d : CATALOG) {
      if (everything || d.key == key) {
        String st = snap.stateOf(d.key);
        if (st == RUNNING) {
          return 'Pack "' +
            d.key +
            '" is still loading. Reset it when it has finished.';
        }
        scope.add(d.key);
      }
    }
    Integer rows = 0;
    for (String p : scope) {
      rows += snap.records.containsKey(p) ? snap.records.get(p) : 0;
    }
    Boolean anyMarker = false;
    for (String p : scope) {
      if (
        snap.startedPacks.contains(p) ||
        snap.donePacks.contains(p) ||
        snap.errors.containsKey(p) ||
        snap.resettingPacks.contains(p)
      ) {
        anyMarker = true;
      }
    }
    if (rows == 0 && !anyMarker) {
      return 'Nothing to remove for "' + (everything ? ALL : key) + '".';
    }
    List<PMS_Demo_Record__c> marks = new List<PMS_Demo_Record__c>();
    for (String p : scope) {
      if (!snap.resettingPacks.contains(p)) {
        marks.add(
          markerRow(p, RESET_MARK, 'Removing ' + System.now().format())
        );
      }
    }
    if (!marks.isEmpty()) {
      insert as user marks;
    }
    enqueueReset(scope);
    return 'Removing ' +
      rows +
      ' demo records in the background (' +
      (everything ? 'all packs' : '"' + key + '"') +
      ').' +
      (everything && key == BASELINE
        ? ' Resetting the baseline removes every pack.'
        : '');
  }

  private static PMS_Demo_Record__c markerRow(
    String pack,
    String prefix,
    String label
  ) {
    return new PMS_Demo_Record__c(
      Name = label.left(80),
      Pack__c = pack,
      Record_Id__c = (prefix + pack).left(18),
      Object_Name__c = MARKER
    );
  }

  // ------------------------------------------------------------------ queueing

  private static void enqueue(List<String> plan) {
    if (Test.isRunningTest()) {
      // A running job cannot chain another one in a test, so all steps are queued up front (they run in order).
      for (Integer i = 0; i < plan.size(); i++) {
        System.enqueueJob(new StepJob(plan, i));
      }
    } else {
      System.enqueueJob(new StepJob(plan, 0));
    }
  }

  private static void enqueueReset(List<String> scope) {
    if (Test.isRunningTest()) {
      for (Integer i = 0; i < 6; i++) {
        System.enqueueJob(new ResetJob(scope));
      }
    } else {
      System.enqueueJob(new ResetJob(scope));
    }
  }

  /** Test hooks: steps per job to emulate a short chain, and what each job used (queries|cpu ms|DML rows|steps). */
  @TestVisible
  private static Integer perJobForTest;
  @TestVisible
  private static List<String> jobStats = new List<String>();

  /** One step of a plan per job; chains the next one when it succeeds. */
  public class StepJob implements Queueable {
    private List<String> plan;
    private Integer index;
    public StepJob(List<String> plan, Integer index) {
      this.plan = plan;
      this.index = index;
    }
    public void execute(QueueableContext qc) {
      // Orgs with a short chain limit (Developer Edition, trials: 5 jobs) get several steps per job so the whole
      // plan fits in the chain; other orgs run one step per job.
      Integer perJob = Test.isRunningTest()
        ? (perJobForTest == null ? 1 : perJobForTest)
        : stepsPerJob(
            plan.size() - index,
            AsyncInfo.getCurrentQueueableStackDepth(),
            AsyncInfo.getMaximumQueueableStackDepth()
          );
      Integer next = index;
      Boolean ok = true;
      for (Integer i = 0; i < perJob && ok && next < plan.size(); i++) {
        ok = PMS_DemoData.runStep(plan, next);
        next++;
      }
      if (ok && next < plan.size() && !Test.isRunningTest()) {
        PMS_DemoData.chainNext(plan, next);
      }
      if (Test.isRunningTest()) {
        jobStats.add(
          Limits.getQueries() +
            '|' +
            Limits.getCpuTime() +
            '|' +
            Limits.getDmlRows() +
            '|' +
            (next - index)
        );
      }
    }
  }

  /** How many steps one chained job should run so that the remaining steps fit in the remaining chain. */
  @TestVisible
  private static Integer stepsPerJob(
    Integer remaining,
    Integer depth,
    Integer maxDepth
  ) {
    if (depth == null) {
      return 1;
    }
    // The maximum is not reported in every org; assume the Developer Edition / trial limit, batching is harmless.
    Integer jobsLeft = Math.max(
      1,
      (maxDepth == null ? ASSUMED_MAX_DEPTH : maxDepth) - depth + 1
    );
    return Math.max(1, (Integer) Math.ceil(remaining / (Decimal) jobsLeft));
  }

  /** Test hook: pretend the Queueable chain limit has been reached. */
  @TestVisible
  private static Boolean forceMaxDepth = false;

  /**
   * Chains the next step. Developer Edition and trial orgs allow only 5 chained Queueable jobs, so when the
   * limit is reached the next step is started by a one-time scheduled job (which starts a fresh chain).
   */
  @TestVisible
  private static void chainNext(List<String> plan, Integer next) {
    if (!forceMaxDepth) {
      try {
        if (!System.isQueueable() || !AsyncInfo.hasMaxStackDepth()) {
          System.enqueueJob(new StepJob(plan, next));
          return;
        }
      } catch (AsyncException e) {
        // chain limit reached (the exact depth check differs between org editions): fall through to the scheduler
        System.debug(LoggingLevel.INFO, 'PMS demo data: ' + e.getMessage());
      }
    }
    Datetime at = Datetime.now().addMinutes(1);
    String cron =
      at.second() +
      ' ' +
      at.minute() +
      ' ' +
      at.hour() +
      ' ' +
      at.day() +
      ' ' +
      at.month() +
      ' ? ' +
      at.year();
    System.schedule(
      'PMS demo data step ' + next + ' ' + Datetime.now().getTime(),
      cron,
      new StepResume(plan, next)
    );
  }

  /** Runs the next step in a scheduled job (fresh limits and chain depth) after the chain limit was reached. */
  public class StepResume implements Schedulable {
    private List<String> plan;
    private Integer index;
    public StepResume(List<String> plan, Integer index) {
      this.plan = plan;
      this.index = index;
    }
    public void execute(SchedulableContext sc) {
      // Runs the step here (a scheduled job has its own fresh limits and chain depth) and chains from here.
      Boolean ok = false;
      try {
        ok = PMS_DemoData.runStep(plan, index);
        if (ok && index + 1 < plan.size()) {
          PMS_DemoData.chainNext(plan, index + 1);
        }
      } catch (Exception e) {
        PMS_DemoData.recordFailure(plan, index, e);
      }
    }
  }

  /** Deletes as much as one transaction allows, then chains itself while there is progress. */
  public class ResetJob implements Queueable {
    private List<String> scope;
    public ResetJob(List<String> scope) {
      this.scope = scope;
    }
    public void execute(QueueableContext qc) {
      String result = PMS_DemoData.resetPass(scope);
      if (result == 'MORE' && !Test.isRunningTest()) {
        System.enqueueJob(new ResetJob(scope));
      }
    }
  }

  // ------------------------------------------------------------------ running a step

  @TestVisible
  private static Boolean runStep(List<String> plan, Integer index) {
    String pack = plan[index].substringBefore(':');
    String step = plan[index].substringAfter(':');
    Ctx c = new Ctx(pack);
    if (c.stopped) {
      // An earlier step failed: leave the rest alone, but make sure no pack of this plan stays RUNNING.
      markPlanFailed(
        plan,
        index,
        c.errorPacks,
        'Not loaded: an earlier step failed.'
      );
      return false;
    }
    Boolean previousFees = PMS_TriggerBypass.policyFees;
    PMS_TriggerBypass.policyFees = true; // no card links or automatic fees for demo bookings
    Savepoint sp = Database.setSavepoint();
    try {
      if (failAt != null && failAt == step) {
        throw new DemoException('Forced failure in step ' + step);
      }
      dispatch(step, c);
      Boolean last =
        index == plan.size() - 1 || !plan[index + 1].startsWith(pack + ':');
      c.finish(last);
      return true;
    } catch (Exception e) {
      Database.rollback(sp);
      recordFailure(plan, index, e);
      return false;
    } finally {
      PMS_TriggerBypass.policyFees = previousFees;
    }
  }

  private static void dispatch(String step, Ctx c) {
    switch on step {
      when 'core' {
        PMS_DemoDataBase.core(c);
      }
      when 'hotel' {
        PMS_DemoDataBase.hotel(c);
      }
      when 'property' {
        PMS_DemoDataBase.property(c);
      }
      when 'projects' {
        PMS_DemoDataWork.projects(c);
      }
      when 'practice' {
        PMS_DemoDataWork.practice(c);
      }
      when 'service' {
        PMS_DemoDataWork.service(c);
      }
      when 'ops' {
        PMS_DemoDataWork.ops(c);
      }
      when 'channels' {
        PMS_DemoDataWork.channels(c);
      }
      when 'billing' {
        PMS_DemoDataBilling.billing(c);
      }
      when 'wave' {
        PMS_DemoDataBilling.wave(c);
      }
      when 'month' {
        PMS_DemoDataBilling.month(c);
      }
      when 'busy' {
        PMS_DemoDataPacks.busy(c);
      }
      when 'incident' {
        PMS_DemoDataPacks.incident(c);
      }
      when 'newclient' {
        PMS_DemoDataPacks.newClient(c);
      }
      when else {
        throw new DemoException('Unknown demo step ' + step);
      }
    }
  }

  /**
   * Records the failure of plan step "index" against its pack, and an ERR marker for every other pack still waiting
   * in the plan (a pack built on a failed baseline would otherwise sit in RUNNING until it goes stale).
   */
  @TestVisible
  private static void recordFailure(
    List<String> plan,
    Integer index,
    Exception e
  ) {
    String pack = plan[index].substringBefore(':');
    String step = plan[index].substringAfter(':');
    System.debug(
      LoggingLevel.ERROR,
      'PMS demo data: step ' + step + ' failed: ' + e.getMessage()
    );
    writeErr(pack, 'Step ' + step + ' failed: ' + e.getMessage());
    markPlanFailed(
      plan,
      index,
      new Set<String>{ pack },
      'Not loaded: step ' + step + ' of "' + pack + '" failed.'
    );
  }

  /** ERR markers for the packs of the plan from "index" on that have none yet. */
  private static void markPlanFailed(
    List<String> plan,
    Integer index,
    Set<String> alreadyFailed,
    String why
  ) {
    Set<String> done = new Set<String>(alreadyFailed);
    for (Integer i = index; i < plan.size(); i++) {
      String p = plan[i].substringBefore(':');
      if (done.add(p)) {
        writeErr(p, why);
      }
    }
  }

  private static void writeErr(String pack, String msg) {
    try {
      insert as user markerRow(pack, ERR_MARK, msg);
    } catch (Exception recordErr) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS demo data: could not record the failure: ' + recordErr.getMessage()
      );
    }
  }

  // ------------------------------------------------------------------ removing

  /**
   * One transaction's worth of deleting. Returns DONE, MORE (call again) or STUCK (records left that cannot be
   * deleted, usually because something outside the demo data now refers to them).
   */
  @TestVisible
  private static String resetPass(List<String> scope) {
    List<PMS_Demo_Record__c> rows = [
      SELECT Id, Name, Pack__c, Record_Id__c, Object_Name__c, Sequence__c
      FROM PMS_Demo_Record__c
      WHERE Pack__c IN :scope
      WITH USER_MODE
      ORDER BY Sequence__c DESC NULLS LAST, Id DESC
      LIMIT 5000
    ];
    if (rows.isEmpty()) {
      return 'DONE';
    }
    List<PMS_Demo_Record__c> data = new List<PMS_Demo_Record__c>();
    List<PMS_Demo_Record__c> markers = new List<PMS_Demo_Record__c>();
    List<PMS_Demo_Record__c> gone = new List<PMS_Demo_Record__c>();
    Set<String> allowed = allowedObjects();
    for (PMS_Demo_Record__c r : rows) {
      if (r.Object_Name__c == MARKER) {
        markers.add(r);
      } else if (isSafeToDelete(r, allowed)) {
        data.add(r);
      } else {
        gone.add(r); // a bad tracking row is dropped; what it points at is never touched
      }
    }
    Boolean allSeen = rows.size() < 5000;
    Boolean failures = false;
    Integer i = 0;
    while (i < data.size()) {
      if (!hasBudget()) {
        allSeen = false;
        break;
      }
      Decimal seq = data[i].Sequence__c;
      List<PMS_Demo_Record__c> batchRows = new List<PMS_Demo_Record__c>();
      List<Id> ids = new List<Id>();
      while (i < data.size() && data[i].Sequence__c == seq) {
        batchRows.add(data[i]);
        ids.add((Id) data[i].Record_Id__c);
        i++;
      }
      // Demo accounts and sites that gained records of their own are kept (deleting them would cascade).
      Set<Id> keep = parentsWithForeignChildren(
        batchRows[0].Object_Name__c,
        ids
      );
      if (!keep.isEmpty()) {
        List<PMS_Demo_Record__c> remaining = new List<PMS_Demo_Record__c>();
        List<Id> remainingIds = new List<Id>();
        for (Integer k = 0; k < ids.size(); k++) {
          if (keep.contains(ids[k])) {
            keptReport.add(
              batchRows[k].Object_Name__c +
                ' ' +
                batchRows[k].Name +
                ' (' +
                ids[k] +
                ')'
            );
            gone.add(batchRows[k]); // forget it, it is no longer demo data
          } else {
            remaining.add(batchRows[k]);
            remainingIds.add(ids[k]);
          }
        }
        batchRows = remaining;
        ids = remainingIds;
      }
      List<Database.DeleteResult> results = ids.isEmpty()
        ? new List<Database.DeleteResult>()
        : Database.delete(ids, false, AccessLevel.USER_MODE);
      for (Integer k = 0; k < results.size(); k++) {
        Boolean removed = results[k].isSuccess();
        if (!removed) {
          for (Database.Error err : results[k].getErrors()) {
            if (err.getStatusCode() == StatusCode.ENTITY_IS_DELETED) {
              removed = true;
            }
          }
        }
        if (removed) {
          gone.add(batchRows[k]);
        } else {
          failures = true;
          System.debug(
            LoggingLevel.WARN,
            'PMS demo data: could not delete ' +
              batchRows[k].Record_Id__c +
              ': ' +
              results[k].getErrors()[0].getMessage()
          );
        }
      }
    }
    if (!keptReport.isEmpty()) {
      System.debug(
        LoggingLevel.WARN,
        'PMS_DEMO|kept|Kept (not demo data any more, they have records of their own): ' +
        String.join(keptReport, ', ')
      );
    }
    Boolean dataLeft = i < data.size() || failures;
    if (!dataLeft && allSeen) {
      gone.addAll(markers);
    }
    if (!gone.isEmpty()) {
      delete as user gone;
    }
    if (!dataLeft && allSeen) {
      return 'DONE';
    }
    if (gone.isEmpty()) {
      return 'STUCK';
    }
    return 'MORE';
  }

  /** Demo records the last reset left alone because someone added their own records under them. */
  @TestVisible
  private static List<String> keptReport = new List<String>();

  /**
   * A tracking row is only trusted when Record_Id__c is a real Id, its object matches Object_Name__c and the object is one
   * the demo data creates.
   */
  @TestVisible
  private static Boolean isSafeToDelete(
    PMS_Demo_Record__c r,
    Set<String> allowed
  ) {
    Id rid;
    try {
      rid = Id.valueOf(r.Record_Id__c);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'PMS demo data: dropping tracking row with a bad Id: ' + r.Record_Id__c
      );
      return false;
    }
    Schema.SObjectType t = rid == null ? null : rid.getSObjectType();
    String actual = t == null ? null : t.getDescribe().getName();
    if (
      actual == null ||
      actual != r.Object_Name__c ||
      !allowed.contains(actual)
    ) {
      System.debug(
        LoggingLevel.WARN,
        'PMS demo data: dropping tracking row ' +
          r.Record_Id__c +
          ' (' +
          r.Object_Name__c +
          ' / ' +
          actual +
          ')'
      );
      return false;
    }
    return true;
  }

  /** Ids of the given demo accounts / sites that have child records which are not tracked as demo data. */
  private static Set<Id> parentsWithForeignChildren(
    String objectName,
    List<Id> ids
  ) {
    Set<Id> keep = new Set<Id>();
    Map<Id, Id> childToParent = new Map<Id, Id>();
    if (objectName == 'Account') {
      for (Contact x : [
        SELECT Id, AccountId
        FROM Contact
        WHERE AccountId IN :ids
        LIMIT 2000
      ]) {
        childToParent.put(x.Id, x.AccountId);
      }
      for (Case x : [
        SELECT Id, AccountId
        FROM Case
        WHERE AccountId IN :ids
        LIMIT 2000
      ]) {
        childToParent.put(x.Id, x.AccountId);
      }
      for (Opportunity x : [
        SELECT Id, AccountId
        FROM Opportunity
        WHERE AccountId IN :ids
        LIMIT 2000
      ]) {
        childToParent.put(x.Id, x.AccountId);
      }
    } else if (objectName == prefix() + 'PMS_Site__c') {
      for (PMS_Space__c x : [
        SELECT Id, Site__c
        FROM PMS_Space__c
        WHERE Site__c IN :ids
        LIMIT 2000
      ]) {
        childToParent.put(x.Id, x.Site__c);
      }
    }
    if (childToParent.isEmpty()) {
      return keep;
    }
    Set<String> childIds = new Set<String>();
    for (Id c : childToParent.keySet()) {
      childIds.add(String.valueOf(c));
    }
    Set<String> tracked = new Set<String>();
    for (PMS_Demo_Record__c t : [
      SELECT Record_Id__c
      FROM PMS_Demo_Record__c
      WHERE Record_Id__c IN :childIds
      WITH USER_MODE
    ]) {
      tracked.add(t.Record_Id__c);
    }
    for (Id c : childToParent.keySet()) {
      if (!tracked.contains(String.valueOf(c))) {
        keep.add(childToParent.get(c));
      }
    }
    return keep;
  }

  private static Boolean hasBudget() {
    return Limits.getDmlStatements() < Limits.getLimitDmlStatements() - 20 &&
      Limits.getQueries() < Limits.getLimitQueries() - 30 &&
      Limits.getCpuTime() < Limits.getLimitCpuTime() * 6 / 10;
  }

  // ------------------------------------------------------------------ build context

  /**
   * What a step needs: today's date, the records earlier steps created (by key), and a way to insert records
   * and track them. Keys are unique across packs, so a pack can refer to baseline records.
   */
  public class Ctx {
    public final Date today = Date.today();
    public final Datetime nowDt = System.now();
    public final String pack;
    public final Id userId = UserInfo.getUserId();
    public Boolean stopped = false;
    public Set<String> errorPacks = new Set<String>();
    public Map<String, Id> refs = new Map<String, Id>();
    private Integer seq = 0;
    private List<SObject> pending = new List<SObject>();
    private List<String> pendingKeys = new List<String>();
    private List<PMS_Demo_Record__c> tracking = new List<PMS_Demo_Record__c>();
    private Map<Schema.SObjectType, String> typeNames = new Map<Schema.SObjectType, String>();

    public Ctx(String pack) {
      this.pack = pack;
      for (PMS_Demo_Record__c r : [
        SELECT Name, Pack__c, Record_Id__c, Object_Name__c, Sequence__c
        FROM PMS_Demo_Record__c
        WITH USER_MODE
        LIMIT 50000
      ]) {
        if (r.Sequence__c != null && r.Sequence__c.intValue() > seq) {
          seq = r.Sequence__c.intValue();
        }
        if (r.Object_Name__c == MARKER) {
          // A failure in this pack, or in the baseline it builds on, stops the remaining steps.
          if (r.Record_Id__c.startsWith(ERR_MARK)) {
            errorPacks.add(r.Pack__c);
            // A failure in this pack, or in the baseline it builds on, stops the remaining steps.
            if (r.Pack__c == pack || r.Pack__c == BASELINE) {
              stopped = true;
            }
          }
        } else {
          refs.put(r.Name, (Id) r.Record_Id__c);
        }
      }
    }

    /** The record created under this key by this or an earlier step. Fails loudly when it is missing. */
    public Id ref(String key) {
      Id i = refs.get(key);
      if (i == null) {
        throw new DemoException(
          'Demo record "' + key + '" is missing. Load the baseline pack first.'
        );
      }
      return i;
    }

    public Id opt(String key) {
      return key == null ? null : refs.get(key);
    }

    public Date day(Integer offset) {
      return today.addDays(offset);
    }

    /** Local date and time, offset in days from today. */
    public Datetime at(Integer dayOffset, Integer hour, Integer minute) {
      return Datetime.newInstance(
        today.addDays(dayOffset),
        Time.newInstance(hour, minute, 0, 0)
      );
    }

    public Id rt(Schema.SObjectType t, String developerName) {
      return PMS_ModuleConfig.recordTypeId(t, developerName);
    }

    /** Queues a record for the next save(). The key is how later steps find it again. */
    public void add(SObject rec, String key) {
      if (rec instanceof PMS_Booking__c) {
        // Mark demo bookings as already mailed, so the real guarantee and check-in jobs never email the
        // (example.com) demo guests or queue card links for them.
        PMS_Booking__c b = (PMS_Booking__c) rec;
        if (b.Card_Link_Sent_At__c == null) {
          b.Card_Link_Sent_At__c = nowDt;
        }
        if (b.Check_In_Invited_At__c == null) {
          b.Check_In_Invited_At__c = nowDt;
        }
      }
      pending.add(rec);
      pendingKeys.add(key);
    }

    /** Inserts everything queued (one DML statement, real triggers) and tracks it for reset. */
    public void save() {
      if (pending.isEmpty()) {
        return;
      }
      insert as user pending;
      seq++;
      for (Integer i = 0; i < pending.size(); i++) {
        SObject r = pending[i];
        Schema.SObjectType t = r.getSObjectType();
        if (!typeNames.containsKey(t)) {
          typeNames.put(t, t.getDescribe().getName());
        }
        refs.put(pendingKeys[i], r.Id);
        tracking.add(
          new PMS_Demo_Record__c(
            Name = pendingKeys[i].left(80),
            Pack__c = pack,
            Record_Id__c = String.valueOf(r.Id),
            Object_Name__c = typeNames.get(t),
            Sequence__c = seq
          )
        );
      }
      pending = new List<SObject>();
      pendingKeys = new List<String>();
    }

    /** Updates records created earlier (for example to link them to something saved afterwards). */
    public void change(List<SObject> recs) {
      if (!recs.isEmpty()) {
        update as user recs;
      }
    }

    /** Writes the tracking rows, and the DONE marker after the last step of a pack. */
    public void finish(Boolean lastStep) {
      save();
      if (lastStep) {
        tracking.add(markerRow(pack, DONE_MARK, 'Loaded ' + nowDt.format()));
      }
      if (!tracking.isEmpty()) {
        insert as user tracking;
      }
      tracking = new List<PMS_Demo_Record__c>();
    }

    /** Plain ASCII for e-mail addresses. */
    public String ascii(String s) {
      return s.toLowerCase()
        .replace('å', 'a')
        .replace('ä', 'a')
        .replace('ö', 'o')
        .replace('é', 'e')
        .replace('ü', 'u')
        .replace(' ', '.')
        .replace('&', '');
    }

    public Account account(
      String key,
      String name,
      String customerType,
      String roles,
      String street,
      String city,
      String zip
    ) {
      Account a = new Account(
        Name = name,
        PMS_Customer_Type__c = customerType,
        PMS_Party_Role__c = roles,
        BillingStreet = street,
        BillingCity = city,
        BillingPostalCode = zip,
        BillingCountry = 'Sweden'
      );
      add(a, key);
      return a;
    }

    public Contact person(
      String key,
      String accountKey,
      String first,
      String last
    ) {
      Contact p = new Contact(
        AccountId = ref(accountKey),
        FirstName = first,
        LastName = last,
        Email = ascii(first + '.' + last) + '@example.com'
      );
      add(p, key);
      return p;
    }
  }
}
