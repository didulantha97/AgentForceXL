/**
 * Moves the objects selected in Access Setup > Objects to a new internal sharing default, safely and
 * step by step. Runs every minute until every object is Done, Failed or Cancelled.
 *
 * Progress lives in the list custom setting PMS_Access_Rollout__c (one row per object).
 *
 * Target Private ("Apply rules"):  Public Read/Write -> Public Read Only -> add the PMS Access Rule
 *                                   sharing reason -> recalculate -> Private -> recalculate -> Done
 * Target Read:                      Public Read/Write -> Public Read Only -> sharing reason -> recalculate -> Done
 * Target ReadWrite (rules off):     Public Read/Write -> Done
 *
 * The recalculation between Read Only and Private writes the Edit shares first, so people keep edit
 * access; the one after Private adds the Read shares (Salesforce refuses Read shares while the
 * default is Public Read Only).
 */
public without sharing class PMS_AccessRollout implements Queueable, Database.AllowsCallouts {
  public static final String STEP_WAITING = 'Waiting';
  public static final String STEP_DONE = 'Done';
  public static final String STEP_FAILED = 'Failed';
  public static final String STEP_CANCELLED = 'Cancelled';
  public static final Set<String> FINAL_STEPS = new Set<String>{
    STEP_DONE,
    STEP_FAILED,
    STEP_CANCELLED
  };

  static final Integer MAX_ATTEMPTS = 3;
  static final Integer MAX_TICKS = 180; // about three hours
  static final Integer RESEND_AFTER_MINUTES = 30;

  @TestVisible
  static Boolean recalcRunningOverride;

  public void execute(QueueableContext ctx) {
    if (PMS_Entitlements.jobsBlocked('PMS_AccessRollout')) {
      return; // suspended: no Metadata API changes; the loop restarts through ensureRunning once the licence is active
    }
    Boolean more = runTick();
    if (more && !Test.isRunningTest()) {
      System.enqueueJob(new PMS_AccessRollout(), 1);
    }
  }

  /** Starts the minute-by-minute loop unless one is already queued or running. */
  public static void ensureRunning() {
    Integer running = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE
        ApexClass.Name = 'PMS_AccessRollout'
        AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
    ];
    if (running == 0 && !Test.isRunningTest()) {
      System.enqueueJob(new PMS_AccessRollout());
    }
  }

  /** Every row, by object API name. Read with SOQL so changes made earlier in the transaction are seen. */
  public static Map<String, PMS_Access_Rollout__c> allRows() {
    Map<String, PMS_Access_Rollout__c> out = new Map<String, PMS_Access_Rollout__c>();
    for (PMS_Access_Rollout__c r : [
      SELECT
        Id,
        Name,
        Target__c,
        Step__c,
        Message__c,
        Requested__c,
        Requested_At__c,
        Recalc_Started__c,
        Attempts__c,
        Ticks__c
      FROM PMS_Access_Rollout__c
      ORDER BY Name
      LIMIT 200
    ]) {
      out.put(r.Name, r);
    }
    return out;
  }

  public static List<PMS_Access_Rollout__c> activeRows() {
    List<PMS_Access_Rollout__c> out = new List<PMS_Access_Rollout__c>();
    for (PMS_Access_Rollout__c r : allRows().values()) {
      if (!FINAL_STEPS.contains(r.Step__c)) {
        out.add(r);
      }
    }
    return out;
  }

  /** One pass over every active row. Returns true when another pass is needed. */
  public Boolean runTick() {
    List<PMS_Access_Rollout__c> rows = activeRows();
    if (rows.isEmpty()) {
      return false;
    }
    Map<String, String> owd = PMS_AccessService.sharingDefaults();
    Boolean recalcRunning = recalcRunningOverride != null
      ? recalcRunningOverride
      : isRecalcRunning();

    Map<String, String> setModel = new Map<String, String>();
    List<String> addReason = new List<String>();
    List<String> recalc = new List<String>();
    Map<String, PMS_Access_Rollout__c> byName = new Map<String, PMS_Access_Rollout__c>();

    for (PMS_Access_Rollout__c r : rows) {
      byName.put(r.Name, r);
      r.Ticks__c = (r.Ticks__c == null ? 0 : r.Ticks__c) + 1;
      if (r.Ticks__c > MAX_TICKS) {
        fail(
          r,
          'Stopped after about three hours without finishing. Check Setup > Sharing Settings, then try again.'
        );
        continue;
      }
      decide(
        r,
        owd.get(r.Name),
        PMS_AccessService.rowCauseFor(r.Name) != null,
        recalcRunning,
        setModel,
        addReason,
        recalc
      );
    }

    // Callouts first: Apex can't call out after writing records in the same transaction.
    try {
      if (!setModel.isEmpty()) {
        apply(PMS_AccessMetadataClient.setSharingModels(setModel), byName);
      }
      if (!addReason.isEmpty()) {
        apply(PMS_AccessMetadataClient.createSharingReasons(addReason), byName);
      }
    } catch (Exception e) {
      for (String name : setModel.keySet()) {
        retryOrFail(byName.get(name), e.getMessage());
      }
      for (String name : addReason) {
        retryOrFail(byName.get(name), e.getMessage());
      }
    }

    if (!recalc.isEmpty() && !Test.isRunningTest()) {
      Database.executeBatch(new PMS_AccessRecalcBatch(recalc, 0), 200);
    }

    update rows;
    for (PMS_Access_Rollout__c r : rows) {
      if (!FINAL_STEPS.contains(r.Step__c)) {
        return true;
      }
    }
    return false;
  }

  /** Works out the next step for one object and records what has to be sent. */
  @TestVisible
  static void decide(
    PMS_Access_Rollout__c r,
    String current,
    Boolean reasonReady,
    Boolean recalcRunning,
    Map<String, String> setModel,
    List<String> addReason,
    List<String> recalc
  ) {
    String target = r.Target__c;
    if (current == null || current == 'ControlledByParent') {
      fail(
        r,
        'This object follows its parent, so its sharing default can\'t be changed here.'
      );
      return;
    }

    if (target == 'ReadWrite') {
      if (current == 'ReadWrite') {
        done(r, 'Public Read/Write: rules are off for these records.');
      } else {
        request(r, 'ReadWrite', 'Changing to Public Read/Write', setModel);
      }
      return;
    }

    // Target Read or Private: Read Only first, then the sharing reason.
    if (current == 'ReadWrite') {
      request(r, 'Read', 'Changing to Public Read Only', setModel);
      r.Recalc_Started__c = false;
      return;
    }
    if (!reasonReady) {
      if (pending(r, 'Reason')) {
        r.Step__c = 'Adding sharing reason';
        return;
      }
      r.Requested__c = 'Reason';
      r.Requested_At__c = System.now();
      r.Step__c = 'Adding sharing reason';
      addReason.add(r.Name);
      return;
    }
    if (current != target) {
      if (target == 'Private') {
        // Read -> Private: write the Edit shares first, then switch.
        if (!r.Recalc_Started__c) {
          startRecalc(r, 'Recalculating', recalc);
        } else if (!recalcRunning) {
          request(r, 'Private', 'Changing to Private', setModel);
          r.Recalc_Started__c = false;
        }
      } else {
        request(r, target, 'Changing to Public Read Only', setModel);
        r.Recalc_Started__c = false;
      }
      return;
    }
    // At the target: one last recalculation, then done.
    if (!r.Recalc_Started__c) {
      startRecalc(
        r,
        target == 'Private' ? 'Recalculating (last step)' : 'Recalculating',
        recalc
      );
    } else if (!recalcRunning) {
      done(
        r,
        target == 'Private'
          ? 'Private: rules decide who sees these records.'
          : 'Public Read Only: everyone can view; rules give edit access.'
      );
    }
  }

  static void request(
    PMS_Access_Rollout__c r,
    String model,
    String step,
    Map<String, String> setModel
  ) {
    r.Step__c = step;
    if (pending(r, model)) {
      return; // already sent; Salesforce is still applying it
    }
    r.Requested__c = model;
    r.Requested_At__c = System.now();
    setModel.put(r.Name, model);
  }

  static Boolean pending(PMS_Access_Rollout__c r, String what) {
    return r.Requested__c == what &&
      r.Requested_At__c != null &&
      r.Requested_At__c.addMinutes(RESEND_AFTER_MINUTES) > System.now();
  }

  static void startRecalc(
    PMS_Access_Rollout__c r,
    String step,
    List<String> recalc
  ) {
    r.Step__c = step;
    r.Recalc_Started__c = true;
    recalc.add(r.Name);
  }

  static void apply(
    List<PMS_AccessMetadataClient.Result> results,
    Map<String, PMS_Access_Rollout__c> byName
  ) {
    for (PMS_AccessMetadataClient.Result res : results) {
      PMS_Access_Rollout__c r = byName.get(res.fullName);
      if (r == null) {
        continue;
      }
      if (res.success) {
        r.Message__c = null;
      } else {
        retryOrFail(r, res.message);
      }
    }
  }

  static void retryOrFail(PMS_Access_Rollout__c r, String message) {
    if (r == null) {
      return;
    }
    r.Attempts__c = (r.Attempts__c == null ? 0 : r.Attempts__c) + 1;
    r.Requested__c = null; // send again on the next pass
    r.Requested_At__c = null;
    if (r.Attempts__c >= MAX_ATTEMPTS) {
      fail(r, message);
    } else {
      r.Message__c = ('Retrying: ' + message).left(255);
    }
  }

  static void fail(PMS_Access_Rollout__c r, String message) {
    r.Step__c = STEP_FAILED;
    r.Message__c = String.valueOf(message).left(255);
  }

  static void done(PMS_Access_Rollout__c r, String message) {
    r.Step__c = STEP_DONE;
    r.Message__c = message.left(255);
  }

  static Boolean isRecalcRunning() {
    return [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE
          ApexClass.Name IN ('PMS_AccessRecalcBatch', 'PMS_AccessGroupSync')
          AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
      ] > 0;
  }
}
