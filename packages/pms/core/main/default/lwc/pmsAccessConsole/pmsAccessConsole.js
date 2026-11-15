import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getOverview from "@salesforce/apex/PMS_AccessConsoleController.getOverview";
import recalculateNow from "@salesforce/apex/PMS_AccessConsoleController.recalculateNow";
import scheduleNightly from "@salesforce/apex/PMS_AccessConsoleController.scheduleNightly";
import checkAccess from "@salesforce/apex/PMS_AccessConsoleController.checkAccess";

const MODULES = ["All", "Property", "Hotel", "Project", "Practice"];

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
  { label: "Rule value", fieldName: "ruleKey", initialWidth: 170 },
  { label: "Sharing default", fieldName: "defaultLabel", initialWidth: 190 },
  {
    label: "Rules applied",
    fieldName: "applied",
    type: "boolean",
    initialWidth: 130
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

export default class PmsAccessConsole extends NavigationMixin(
  LightningElement
) {
  ruleColumns = RULE_COLUMNS;
  teamColumns = TEAM_COLUMNS;
  objectColumns = OBJECT_COLUMNS;
  jobColumns = JOB_COLUMNS;

  loading = true;
  error;
  data;
  checkUserId;
  checkRecord = "";
  checkResult;
  checking = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.data = await getOverview();
      this.error = undefined;
    } catch (e) {
      this.error = this.message(e);
    } finally {
      this.loading = false;
    }
  }

  message(e) {
    return (
      (e && e.body && e.body.message) ||
      (e && e.message) ||
      "Something went wrong."
    );
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
      let note = "";
      if (!o.restricted) {
        note =
          "Everyone can edit these while the default is Public Read/Write. Set it to Private in Sharing Settings to let the rules decide.";
      } else if (!o.reasonReady) {
        note =
          "Deploy the PMS Access Rule sharing reason (post-owd folder) before rules can be applied.";
      }
      return {
        ...o,
        defaultLabel: DEFAULT_LABELS[o.sharingDefault] || o.sharingDefault,
        applied: o.restricted && o.reasonReady,
        note
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
