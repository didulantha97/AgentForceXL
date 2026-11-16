import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import getOverview from "@salesforce/apex/PMS_AccessConsoleController.getOverview";
import recalculateNow from "@salesforce/apex/PMS_AccessConsoleController.recalculateNow";
import scheduleNightly from "@salesforce/apex/PMS_AccessConsoleController.scheduleNightly";
import checkAccess from "@salesforce/apex/PMS_AccessConsoleController.checkAccess";
import startRollout from "@salesforce/apex/PMS_AccessConsoleController.startRollout";
import cancelRollout from "@salesforce/apex/PMS_AccessConsoleController.cancelRollout";

const MODULES = ["All", "Property", "Hotel", "Project", "Practice"];
const POLL_MS = 15000;

const RULE_COLUMNS = [
  {
    label: "Rule",
    fieldName: "url",
    type: "url",
    typeAttributes: { label: { fieldName: "Name" } },
    initialWidth: 110
  },
  { label: "Team", fieldName: "teamName" },
  { label: "Site", fieldName: "siteName" },
  { label: "Module", fieldName: "Module__c", initialWidth: 110 },
  { label: "Records", fieldName: "records", wrapText: true },
  { label: "Access", fieldName: "Access_Level__c", initialWidth: 90 },
  {
    label: "Active",
    fieldName: "Active__c",
    type: "boolean",
    initialWidth: 80
  },
  {
    type: "action",
    typeAttributes: {
      rowActions: [
        { label: "Edit", name: "edit" },
        { label: "Open", name: "view" }
      ]
    }
  }
];

const TEAM_COLUMNS = [
  {
    label: "Team",
    fieldName: "url",
    type: "url",
    typeAttributes: { label: { fieldName: "Name" } }
  },
  { label: "Members", fieldName: "members", initialWidth: 120 },
  {
    label: "Hide amounts",
    fieldName: "Hide_Amounts__c",
    type: "boolean",
    initialWidth: 130
  },
  {
    label: "Hide customer details",
    fieldName: "Hide_Customer_Details__c",
    type: "boolean",
    initialWidth: 180
  },
  {
    label: "Active",
    fieldName: "Active__c",
    type: "boolean",
    initialWidth: 80
  },
  { label: "Description", fieldName: "Description__c", wrapText: true },
  {
    type: "action",
    typeAttributes: {
      rowActions: [
        { label: "Edit", name: "edit" },
        { label: "Open", name: "view" }
      ]
    }
  }
];

const OBJECT_COLUMNS = [
  { label: "Records", fieldName: "label" },
  { label: "Rule value", fieldName: "ruleKey", initialWidth: 160 },
  { label: "Sharing default", fieldName: "defaultLabel", initialWidth: 170 },
  {
    label: "Rules applied",
    fieldName: "applied",
    type: "boolean",
    initialWidth: 120
  },
  {
    label: "Progress",
    fieldName: "progress",
    wrapText: true,
    initialWidth: 230,
    cellAttributes: { class: { fieldName: "progressCls" } }
  },
  { label: "Note", fieldName: "note", wrapText: true }
];

const JOB_COLUMNS = [
  { label: "Job", fieldName: "className" },
  { label: "Status", fieldName: "status", initialWidth: 120 },
  { label: "Batches", fieldName: "progress", initialWidth: 100 },
  { label: "Errors", fieldName: "errors", type: "number", initialWidth: 90 },
  {
    label: "Started",
    fieldName: "created",
    type: "date",
    typeAttributes: {
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit"
    }
  },
  {
    label: "Finished",
    fieldName: "completed",
    type: "date",
    typeAttributes: {
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit"
    }
  }
];

const DEFAULT_LABELS = {
  ReadWrite: "Public Read/Write",
  Read: "Public Read Only",
  Private: "Private",
  ControlledByParent: "Controlled by parent"
};

const TARGET_OPTIONS = [
  {
    label: "Public Read Only (everyone views, rules give edit)",
    value: "Read"
  },
  { label: "Private (only where rules are already applied)", value: "Private" },
  { label: "Public Read/Write (turn rules off)", value: "ReadWrite" }
];

const TARGET_LABELS = {
  Private: "Private",
  Read: "Public Read Only",
  ReadWrite: "Public Read/Write"
};

export default class PmsAccessConsole extends NavigationMixin(
  LightningElement
) {
  ruleColumns = RULE_COLUMNS;
  teamColumns = TEAM_COLUMNS;
  objectColumns = OBJECT_COLUMNS;
  jobColumns = JOB_COLUMNS;
  targetOptions = TARGET_OPTIONS;

  loading = true;
  error;
  data;
  activeTab = "overview";
  checkUserId;
  checkRecord = "";
  checkResult;
  checking = false;

  selectedObjects = [];
  bulkTarget;
  busy = false;
  pollTimer;

  connectedCallback() {
    this.load();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  async load(silent) {
    if (!silent) {
      this.loading = true;
    }
    try {
      this.data = await getOverview();
      this.error = undefined;
    } catch (e) {
      if (!silent) {
        this.error = this.message(e);
      }
    } finally {
      this.loading = false;
      this.syncPolling();
    }
  }

  /** Refresh every 15 seconds while a change is running, so progress shows without reloading. */
  syncPolling() {
    if (this.rolloutActive && !this.pollTimer) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.pollTimer = setInterval(() => this.load(true), POLL_MS);
    } else if (!this.rolloutActive) {
      this.stopPolling();
    }
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  message(e) {
    return (
      (e && e.body && e.body.message) ||
      (e && e.message) ||
      "Something went wrong."
    );
  }

  handleTab(event) {
    this.activeTab = event.target.value;
  }

  get canManage() {
    return this.data && this.data.canManage;
  }

  get cannotManage() {
    return !this.canManage;
  }

  get rules() {
    if (!this.data) return [];
    return this.data.rules.map((r) => ({
      ...r,
      url: "/" + r.Id,
      teamName: r.Team__r ? r.Team__r.Name : "",
      siteName: r.Site__r ? r.Site__r.Name : "Every site",
      records: r.Objects__c
        ? r.Objects__c.split(";").join(", ").replace(/_/g, " ")
        : "Every kind of record"
    }));
  }

  get teams() {
    if (!this.data) return [];
    return this.data.teams.map((t) => ({
      ...t,
      url: "/" + t.Id,
      members: t.All_Internal_Users__c
        ? "Everyone"
        : String(t.Member_Count__c || 0)
    }));
  }

  get objects() {
    if (!this.data) return [];
    return this.data.objects.map((o) => {
      const applied = o.restricted && o.reasonReady;
      let note = "";
      if (!o.restricted) {
        note =
          "Everyone can edit these while the default is Public Read/Write. Select it and use Apply rules to let the rules decide.";
      } else if (!o.reasonReady) {
        note =
          "The PMS Access Rule sharing reason is missing. Apply rules adds it.";
      } else if (o.sharingDefault === "Read") {
        note =
          "Everyone can view these; rules decide who can edit. Apply rules makes it Private.";
      }
      let progress = "";
      let progressCls = "";
      if (o.rolloutStep) {
        const target = TARGET_LABELS[o.rolloutTarget] || o.rolloutTarget;
        if (o.rolloutActive) {
          progress =
            `${o.rolloutStep} → ${target}` +
            (o.rolloutMessage ? ` (${o.rolloutMessage})` : "");
          progressCls = "slds-text-color_default";
        } else if (o.rolloutStep === "Failed") {
          progress = `Failed: ${o.rolloutMessage || "see Setup > Sharing Settings"}`;
          progressCls = "slds-text-color_error";
        } else if (o.rolloutStep === "Cancelled") {
          progress = o.rolloutMessage || "Stopped.";
          progressCls = "slds-text-color_weak";
        } else {
          progress = o.rolloutMessage || "Done.";
          progressCls = "slds-text-color_success";
        }
      }
      return {
        ...o,
        defaultLabel: DEFAULT_LABELS[o.sharingDefault] || o.sharingDefault,
        applied,
        note,
        progress,
        progressCls
      };
    });
  }

  get jobs() {
    if (!this.data) return [];
    return this.data.jobs.map((j) => ({
      ...j,
      progress: j.total ? `${j.processed}/${j.total}` : ""
    }));
  }

  get hasJobs() {
    return this.jobs.length > 0;
  }

  get appliedCount() {
    return this.objects.filter((o) => o.applied).length;
  }

  get objectCount() {
    return this.objects.length;
  }

  get notAppliedYet() {
    return this.data && this.appliedCount === 0;
  }

  get nightlyLabel() {
    return this.data && this.data.nightlyScheduled
      ? "Nightly sync is scheduled"
      : "Schedule nightly sync";
  }

  get nightlyDisabled() {
    return this.cannotManage || (this.data && this.data.nightlyScheduled);
  }

  /** Matrix: one row per team, one column per module, cells list the sites and access. */
  get matrix() {
    if (!this.data) return [];
    const byTeam = new Map();
    this.data.teams.forEach((t) =>
      byTeam.set(t.Id, {
        id: t.Id,
        url: "/" + t.Id,
        name: t.Name,
        inactive: !t.Active__c,
        cells: MODULES.map((m) => ({ key: m, items: [] }))
      })
    );
    this.data.rules
      .filter((r) => r.Active__c)
      .forEach((r) => {
        const row = byTeam.get(r.Team__c);
        if (!row) return;
        const cell = row.cells.find((c) => c.key === (r.Module__c || "All"));
        const scope = r.Objects__c
          ? " · " + r.Objects__c.split(";").length + " kinds"
          : "";
        cell.items.push({
          key: r.Id,
          text: (r.Site__r ? r.Site__r.Name : "Every site") + scope,
          level: r.Access_Level__c,
          cls:
            r.Access_Level__c === "Edit" ? "pill pill-edit" : "pill pill-read"
        });
      });
    return Array.from(byTeam.values());
  }

  get modules() {
    return MODULES.map((m) => (m === "All" ? "Every module" : m));
  }

  get hasTeams() {
    return this.data && this.data.teams.length > 0;
  }

  // ------------------------------------------------------------- bulk sharing defaults

  get rolloutActive() {
    return !!(this.data && this.data.rolloutActive);
  }

  get selectedCount() {
    return this.selectedObjects.length;
  }

  get applyLabel() {
    return this.selectedCount
      ? `Apply rules (${this.selectedCount})`
      : "Apply rules";
  }

  get bulkDisabled() {
    return this.busy || this.selectedCount === 0;
  }

  get setDisabled() {
    return this.bulkDisabled || !this.bulkTarget;
  }

  handleObjectSelection(event) {
    this.selectedObjects = event.detail.selectedRows.map((r) => r.objectApi);
  }

  handleTarget(event) {
    this.bulkTarget = event.detail.value;
  }

  selectNotApplied() {
    this.selectedObjects = this.objects
      .filter(
        (o) =>
          !(o.applied && o.sharingDefault === "Private") && !o.rolloutActive
      )
      .map((o) => o.objectApi);
  }

  clearSelection() {
    this.selectedObjects = [];
  }

  selectedLabels() {
    const set = new Set(this.selectedObjects);
    const names = this.objects
      .filter((o) => set.has(o.objectApi))
      .map((o) => o.label);
    return names.length > 6
      ? names.slice(0, 6).join(", ") + ` and ${names.length - 6} more`
      : names.join(", ");
  }

  async handleApplyRules() {
    const ok = await LightningConfirm.open({
      label: `Apply rules to ${this.selectedCount} kind(s) of records?`,
      theme: "warning",
      message:
        `${this.selectedLabels()}.\n\n` +
        "Each one goes Public Read Only, gets the PMS Access Rule sharing reason, is recalculated, goes Private and is recalculated again. " +
        "That takes a few minutes per step. Until the first recalculation finishes, staff who don't own a record can view it but may not be able to edit it. " +
        "Afterwards, people only see the records their teams' rules give them, so check the rules first."
    });
    if (ok) {
      await this.runRollout("apply", null);
    }
  }

  async handleSetDefault() {
    const target = TARGET_LABELS[this.bulkTarget];
    const warn =
      this.bulkTarget === "ReadWrite"
        ? "Rules stop applying to these records and every staff member can view and edit them again."
        : this.bulkTarget === "Read"
          ? "Everyone can still view these records. Only owners and teams with an Edit rule can change them, once the recalculation has run."
          : "Only records already under rules (Public Read Only with the sharing reason) can go Private here. Use Apply rules for the others.";
    const ok = await LightningConfirm.open({
      label: `Set ${this.selectedCount} kind(s) of records to ${target}?`,
      theme: this.bulkTarget === "ReadWrite" ? "info" : "warning",
      message: `${this.selectedLabels()}.\n\n${warn}`
    });
    if (ok) {
      await this.runRollout("set", this.bulkTarget);
    }
  }

  async runRollout(mode, target) {
    this.busy = true;
    try {
      const n = await startRollout({
        objectApis: this.selectedObjects,
        mode,
        target
      });
      this.toast(
        "Started",
        `Changing ${n} kind(s) of records. Progress shows in the Progress column.`,
        "success"
      );
      this.selectedObjects = [];
      this.bulkTarget = undefined;
      await this.load(true);
    } catch (e) {
      this.toast("Could not start", this.message(e), "error");
    } finally {
      this.busy = false;
    }
  }

  async handleStop() {
    const only = this.selectedObjects.length ? this.selectedObjects : null;
    const ok = await LightningConfirm.open({
      label: only
        ? "Stop changes for the selected records?"
        : "Stop all running changes?",
      theme: "warning",
      message:
        "A step already sent to Salesforce still finishes, so an object may stay at Public Read Only. You can start again later."
    });
    if (!ok) return;
    this.busy = true;
    try {
      const n = await cancelRollout({ objectApis: only });
      this.toast("Stopped", `${n} change(s) stopped.`, "success");
      await this.load(true);
    } catch (e) {
      this.toast("Could not stop", this.message(e), "error");
    } finally {
      this.busy = false;
    }
  }

  // ------------------------------------------------------------- actions

  navNew(objectApiName) {
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: { objectApiName, actionName: "new" }
    });
  }

  handleNewTeam() {
    this.navNew("PMS_Access_Team__c");
  }

  handleNewRule() {
    this.navNew("PMS_Access_Rule__c");
  }

  handleRowAction(event) {
    const { action, row } = event.detail;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: row.Id,
        actionName: action.name === "edit" ? "edit" : "view"
      }
    });
  }

  async handleRecalc() {
    try {
      await recalculateNow();
      this.toast(
        "Recalculation started",
        "Teams are synced first, then every restricted object. Refresh in a minute to see progress.",
        "success"
      );
      // A short delay lets the queued recalculation job update before refreshing the console.
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => this.load(), 3000);
    } catch (e) {
      this.toast("Could not start", this.message(e), "error");
    }
  }

  async handleNightly() {
    try {
      const r = await scheduleNightly();
      this.toast(
        r === "already" ? "Already scheduled" : "Scheduled",
        "The access sync runs every night at 01:30.",
        "success"
      );
      this.load();
    } catch (e) {
      this.toast("Could not schedule", this.message(e), "error");
    }
  }

  handleRefresh() {
    this.load();
  }

  handleUser(event) {
    this.checkUserId = event.detail.recordId;
  }

  handleRecord(event) {
    this.checkRecord = event.target.value;
  }

  get checkDisabled() {
    return (
      this.cannotManage ||
      !this.checkUserId ||
      !this.checkRecord ||
      this.checking
    );
  }

  async handleCheck() {
    this.checking = true;
    this.checkResult = undefined;
    try {
      const r = await checkAccess({
        userId: this.checkUserId,
        recordIdOrUrl: this.checkRecord
      });
      const ex = r.explanation || {};
      this.checkResult = {
        ...r,
        verdict: r.hasEdit
          ? "Can view and edit"
          : r.hasRead
            ? "Can view, not edit"
            : "Cannot see this record",
        verdictCls: r.hasEdit
          ? "verdict verdict-edit"
          : r.hasRead
            ? "verdict verdict-read"
            : "verdict verdict-none",
        where: [ex.objectLabel, ex.siteName, ex.module]
          .filter(Boolean)
          .join(" · "),
        defaultLabel: DEFAULT_LABELS[ex.sharingDefault] || ex.sharingDefault,
        granting: ex.grantingRules || [],
        others: ex.otherMatchingRules || [],
        hasGranting: (ex.grantingRules || []).length > 0,
        hasOthers: (ex.otherMatchingRules || []).length > 0,
        notRestricted: ex.restricted === false
      };
    } catch (e) {
      this.toast("Check failed", this.message(e), "error");
    } finally {
      this.checking = false;
    }
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
