import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { encodeDefaultFieldValues } from "lightning/pageReferenceUtils";
import { refreshApex } from "@salesforce/apex";
import getHome from "@salesforce/apex/PMS_HomeController.getHome";
import createInvoiceLink from "@salesforce/apex/PMS_StripeCheckout.createInvoiceLink";

/*
 * PMS app home page. One component serves every app; the "module" property (set per page in
 * Lightning App Builder) picks the KPIs, charts, queues and quick actions.
 */

const MODULE_META = {
  Admin: {
    title: "PMS Admin",
    tagline: "Every site, booking and invoice at a glance",
    icon: "standard:home"
  },
  Hotel: {
    title: "Hotel",
    tagline: "Front desk, occupancy and guests today",
    icon: "standard:service_territory"
  },
  Property: {
    title: "Property",
    tagline: "Units, leases, rent and maintenance",
    icon: "standard:household"
  },
  Projects: {
    title: "Projects",
    tagline: "Delivery, risks, time and client approvals",
    icon: "standard:work_plan"
  },
  Practice: {
    title: "Practice",
    tagline: "Diary, clients, matters and billing",
    icon: "standard:client"
  }
};

// type: tab (app page / nav item), new (record create with defaults), list (object list view), dashboard, reports
const QUICK_ACTIONS = {
  Admin: [
    {
      key: "newBooking",
      label: "New booking",
      icon: "utility:event",
      type: "tab",
      target: "New_Booking"
    },
    {
      key: "newSite",
      label: "New site",
      icon: "utility:company",
      type: "new",
      target: "PMS_Site__c"
    },
    {
      key: "newSpace",
      label: "New space",
      icon: "utility:apps",
      type: "new",
      target: "PMS_Space__c",
      site: "Site__c"
    },
    {
      key: "newAccount",
      label: "New customer",
      icon: "utility:people",
      type: "new",
      target: "Account"
    },
    {
      key: "newCase",
      label: "Log a request",
      icon: "utility:case",
      type: "new",
      target: "Case",
      site: "PMS_Site__c"
    },
    {
      key: "overdue",
      label: "Overdue invoices",
      icon: "utility:warning",
      type: "list",
      target: "PMS_Invoice__c",
      listView: "Overdue_Invoices"
    },
    {
      key: "dashboard",
      label: "PMS Overview",
      icon: "utility:chart",
      type: "dashboard"
    },
    {
      key: "reports",
      label: "Reports",
      icon: "utility:metrics",
      type: "reports"
    },
    {
      key: "payLink",
      label: "Send pay link",
      icon: "utility:link",
      type: "paylink"
    },
    {
      key: "access",
      label: "Access setup",
      icon: "utility:lock",
      type: "tab",
      target: "PMS_Access_Setup",
      needs: "access"
    }
  ],
  Hotel: [
    {
      key: "frontDesk",
      label: "Front desk",
      icon: "utility:checkin",
      type: "tab",
      target: "Front_Desk"
    },
    {
      key: "newBooking",
      label: "New reservation",
      icon: "utility:event",
      type: "tab",
      target: "New_Booking"
    },
    {
      key: "arrivals",
      label: "Arrivals",
      icon: "utility:forward",
      type: "list",
      target: "PMS_Booking__c",
      listView: "Arrivals_Today"
    },
    {
      key: "departures",
      label: "Departures",
      icon: "utility:back",
      type: "list",
      target: "PMS_Booking__c",
      listView: "Departures_Today"
    },
    {
      key: "housekeeping",
      label: "Rooms to clean",
      icon: "utility:sparkles",
      type: "list",
      target: "PMS_Space__c",
      listView: "Rooms_To_Clean"
    },
    {
      key: "groupBlock",
      label: "Group block",
      icon: "utility:groups",
      type: "new",
      target: "PMS_Group_Block__c",
      site: "Site__c"
    },
    {
      key: "guestRequest",
      label: "Guest request",
      icon: "utility:case",
      type: "new",
      target: "Case",
      site: "PMS_Site__c",
      defaults: { PMS_Module__c: "Hotel", Origin: "Phone" }
    },
    {
      key: "payment",
      label: "Take payment",
      icon: "utility:moneybag",
      type: "new",
      target: "PMS_Payment__c",
      today: "Received_Date__c"
    },
    {
      key: "payLink",
      label: "Send pay link",
      icon: "utility:link",
      type: "paylink"
    }
  ],
  Property: [
    {
      key: "newLease",
      label: "New lease",
      icon: "utility:contract",
      type: "tab",
      target: "New_Booking"
    },
    {
      key: "newListing",
      label: "List a unit",
      icon: "utility:announcement",
      type: "new",
      target: "PMS_Listing__c",
      site: "Site__c"
    },
    {
      key: "maintenance",
      label: "Log maintenance",
      icon: "utility:case",
      type: "new",
      target: "Case",
      site: "PMS_Site__c",
      defaults: { PMS_Module__c: "Property" }
    },
    {
      key: "workOrder",
      label: "New work order",
      icon: "utility:custom_apps",
      type: "new",
      target: "PMS_Work_Order__c",
      site: "Site__c"
    },
    {
      key: "inspection",
      label: "Schedule inspection",
      icon: "utility:preview",
      type: "new",
      target: "PMS_Inspection__c",
      site: "Site__c"
    },
    {
      key: "payment",
      label: "Record rent",
      icon: "utility:moneybag",
      type: "new",
      target: "PMS_Payment__c",
      today: "Received_Date__c"
    },
    {
      key: "vacant",
      label: "Vacant units",
      icon: "utility:open_folder",
      type: "list",
      target: "PMS_Space__c",
      listView: "Vacant_Units"
    },
    {
      key: "statements",
      label: "Owner statements",
      icon: "utility:metrics",
      type: "list",
      target: "PMS_Owner_Statement__c",
      listView: "All"
    },
    {
      key: "quotes",
      label: "Vendor quotes",
      icon: "utility:quote",
      type: "list",
      target: "PMS_Vendor_Quote__c"
    },
    {
      key: "payLink",
      label: "Send pay link",
      icon: "utility:link",
      type: "paylink"
    }
  ],
  Projects: [
    {
      key: "newProject",
      label: "New project",
      icon: "utility:work_order_type",
      type: "new",
      target: "PMS_Project__c",
      site: "Site__c"
    },
    {
      key: "newTask",
      label: "New task",
      icon: "utility:task",
      type: "new",
      target: "PMS_Project_Task__c"
    },
    {
      key: "logTime",
      label: "Log time",
      icon: "utility:clock",
      type: "new",
      target: "PMS_Time_Entry__c",
      today: "Entry_Date__c",
      defaults: { Billable__c: true }
    },
    {
      key: "raid",
      label: "Raise risk or issue",
      icon: "utility:warning",
      type: "new",
      target: "PMS_RAID_Item__c"
    },
    {
      key: "changeOrder",
      label: "Change request",
      icon: "utility:approval",
      type: "new",
      target: "PMS_Approval_Request__c"
    },
    {
      key: "milestones",
      label: "Milestones",
      icon: "utility:priority",
      type: "list",
      target: "PMS_Milestone__c"
    },
    {
      key: "openTasks",
      label: "Open tasks",
      icon: "utility:list",
      type: "list",
      target: "PMS_Project_Task__c",
      listView: "Open_Tasks"
    },
    {
      key: "resources",
      label: "Resources",
      icon: "utility:people",
      type: "list",
      target: "PMS_Resource__c"
    },
    {
      key: "payLink",
      label: "Send pay link",
      icon: "utility:link",
      type: "paylink"
    }
  ],
  Practice: [
    {
      key: "diary",
      label: "Diary",
      icon: "utility:monthlyview",
      type: "tab",
      target: "Diary"
    },
    {
      key: "newBooking",
      label: "Book appointment",
      icon: "utility:event",
      type: "tab",
      target: "New_Booking"
    },
    {
      key: "newClient",
      label: "New client",
      icon: "utility:adduser",
      type: "new",
      target: "Contact"
    },
    {
      key: "newMatter",
      label: "Open a matter",
      icon: "utility:case",
      type: "new",
      target: "PMS_Matter__c",
      site: "Site__c",
      defaults: { Status__c: "Intake" }
    },
    {
      key: "intake",
      label: "Intake form",
      icon: "utility:form",
      type: "new",
      target: "PMS_Intake_Form__c"
    },
    {
      key: "logTime",
      label: "Log time",
      icon: "utility:clock",
      type: "new",
      target: "PMS_Time_Entry__c",
      today: "Entry_Date__c",
      defaults: { Billable__c: true }
    },
    {
      key: "payment",
      label: "Record payment",
      icon: "utility:moneybag",
      type: "new",
      target: "PMS_Payment__c",
      today: "Received_Date__c"
    },
    {
      key: "appointments",
      label: "Upcoming",
      icon: "utility:event",
      type: "list",
      target: "PMS_Booking__c",
      listView: "Upcoming_Appointments"
    },
    {
      key: "payLink",
      label: "Send pay link",
      icon: "utility:link",
      type: "paylink"
    }
  ]
};

const OPEN_INVOICE_STATUSES = ["Issued", "Partially Paid", "Overdue"];

const TONE_CLASS = {
  success: "tone-success",
  warning: "tone-warning",
  error: "tone-error",
  neutral: "tone-neutral"
};

function isoToday() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export default class PmsAppHome extends NavigationMixin(LightningElement) {
  /** Admin, Hotel, Property, Projects or Practice. */
  @api module = "Admin";
  /** App Builder checkboxes: leave unticked to show the section. */
  @api hideQuickActions = false;
  @api hideAgenda = false;
  /** Minutes between automatic refreshes; 0 turns it off. */
  @api refreshMinutes = 5;

  siteId = "";
  data;
  error;
  loading = true;
  refreshing = false;
  activeSection;
  wired;
  timer;

  // pay link panel
  payOpen = false;
  payInvoiceId;
  payResult;
  payError;
  payLoading = false;
  payCopied = false;

  connectedCallback() {
    try {
      this.siteId = window.localStorage.getItem(this.storageKey) || "";
    } catch {
      this.siteId = "";
    }
    const minutes = Number(this.refreshMinutes);
    if (minutes > 0) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.timer = setInterval(() => this.refresh(), minutes * 60000);
    }
  }

  disconnectedCallback() {
    if (this.timer) {
      clearInterval(this.timer);
    }
  }

  get storageKey() {
    return `pmsAppHome.site.${this.module}`;
  }

  @wire(getHome, { module: "$module", siteId: "$siteId" })
  wiredHome(result) {
    this.wired = result;
    const { data, error } = result;
    if (data) {
      this.data = data;
      this.error = undefined;
      this.loading = false;
      if (
        !this.activeSection ||
        !data.sections.some((s) => s.key === this.activeSection)
      ) {
        const firstWithItems = data.sections.find((s) => s.total > 0);
        this.activeSection = (firstWithItems || data.sections[0] || {}).key;
      }
    } else if (error) {
      this.error = error;
      this.loading = false;
    }
  }

  // ---------------------------------------------------------------- header

  get meta() {
    return MODULE_META[this.module] || MODULE_META.Admin;
  }

  get greeting() {
    const h = new Date().getHours();
    const part =
      h < 5
        ? "Good evening"
        : h < 12
          ? "Good morning"
          : h < 18
            ? "Good afternoon"
            : "Good evening";
    const name = this.data?.userFirstName;
    return name ? `${part}, ${name}` : part;
  }

  get todayLabel() {
    return new Intl.DateTimeFormat(undefined, {
      weekday: "long",
      day: "numeric",
      month: "long"
    }).format(new Date());
  }

  get siteOptions() {
    const all = {
      label:
        this.module === "Admin"
          ? "All sites"
          : `All ${this.meta.title.toLowerCase()} sites`,
      value: ""
    };
    return [
      all,
      ...(this.data?.sites || []).map((s) => ({
        label: s.label,
        value: s.value
      }))
    ];
  }

  get hasSiteChoice() {
    return (this.data?.sites || []).length > 1;
  }

  get updatedLabel() {
    if (!this.data?.generatedAt) return "";
    const t = new Intl.DateTimeFormat(undefined, {
      hour: "2-digit",
      minute: "2-digit"
    }).format(new Date(this.data.generatedAt));
    return `Updated ${t}`;
  }

  get currencyCode() {
    return this.data?.currencyCode || "SEK";
  }

  get errorText() {
    const e = this.error;
    if (!e) return "";
    return (
      e.body?.message || e.message || "Something went wrong loading this page."
    );
  }

  get hasWarnings() {
    return (this.data?.warnings || []).length > 0;
  }

  get warningSummary() {
    const n = this.data?.warnings?.length || 0;
    return `${n} part${n === 1 ? "" : "s"} of this page could not load (usually a missing permission). Ask your admin.`;
  }

  handleSiteChange(evt) {
    this.siteId = evt.detail.value;
    try {
      window.localStorage.setItem(this.storageKey, this.siteId);
    } catch {
      // storage can be unavailable; the choice just won't be remembered
    }
  }

  async refresh() {
    if (!this.wired || this.refreshing) return;
    this.refreshing = true;
    try {
      await refreshApex(this.wired);
    } finally {
      this.refreshing = false;
    }
  }

  // ---------------------------------------------------------------- quick actions

  get quickActionsVisible() {
    return !this.hideQuickActions;
  }

  get agendaVisible() {
    return !this.hideAgenda;
  }

  get quickActions() {
    return (QUICK_ACTIONS[this.module] || []).filter(
      (a) =>
        (a.type !== "dashboard" || this.data?.dashboardId) &&
        (a.needs !== "access" || this.data?.canManageAccess)
    );
  }

  handleQuickAction(evt) {
    const key = evt.currentTarget.dataset.key;
    const action = (QUICK_ACTIONS[this.module] || []).find(
      (a) => a.key === key
    );
    if (!action) return;
    switch (action.type) {
      case "tab":
        this[NavigationMixin.Navigate]({
          type: "standard__navItemPage",
          attributes: { apiName: action.target }
        });
        break;
      case "list":
        this.openList(action.target, action.listView);
        break;
      case "dashboard":
        this[NavigationMixin.Navigate]({
          type: "standard__recordPage",
          attributes: {
            recordId: this.data.dashboardId,
            objectApiName: "Dashboard",
            actionName: "view"
          }
        });
        break;
      case "paylink":
        this.openPayLink();
        break;
      case "reports":
        this[NavigationMixin.Navigate]({
          type: "standard__objectPage",
          attributes: { objectApiName: "Report", actionName: "home" }
        });
        break;
      default: {
        const defaults = { ...(action.defaults || {}) };
        if (action.site && this.siteId) defaults[action.site] = this.siteId;
        if (action.today) defaults[action.today] = isoToday();
        const pageRef = {
          type: "standard__objectPage",
          attributes: { objectApiName: action.target, actionName: "new" }
        };
        if (Object.keys(defaults).length) {
          pageRef.state = {
            defaultFieldValues: encodeDefaultFieldValues(defaults)
          };
        }
        this[NavigationMixin.Navigate](pageRef);
      }
    }
  }

  openList(objectApiName, listView) {
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: { objectApiName, actionName: "list" },
      state: { filterName: listView || "Recent" }
    });
  }

  // ---------------------------------------------------------------- access notice

  get hasAccessNotice() {
    return !!this.data?.accessNotice;
  }

  get accessNoticeClass() {
    return `access-note access-${this.data?.accessTone || "neutral"}`;
  }

  openAccessSetup() {
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName: "PMS_Access_Setup" }
    });
  }

  // ---------------------------------------------------------------- pay link

  get invoiceFilter() {
    return {
      criteria: [
        { fieldPath: "Status__c", operator: "in", value: OPEN_INVOICE_STATUSES }
      ]
    };
  }

  get invoiceDisplayInfo() {
    return { additionalFields: ["Status__c"] };
  }

  get payCreateDisabled() {
    return !this.payInvoiceId || this.payLoading;
  }

  get payCreateLabel() {
    return this.payResult ? "Create new link" : "Create link";
  }

  get payExpires() {
    if (!this.payResult?.expiresAt) return "";
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short"
    }).format(new Date(this.payResult.expiresAt));
  }

  openPayLink() {
    this.payOpen = true;
    this.payInvoiceId = undefined;
    this.payResult = undefined;
    this.payError = undefined;
    this.payCopied = false;
  }

  closePayLink() {
    this.payOpen = false;
  }

  handlePayKey(evt) {
    if (evt.key === "Escape") {
      this.closePayLink();
    }
  }

  handlePayInvoice(evt) {
    this.payInvoiceId = evt.detail.recordId;
    this.payResult = undefined;
    this.payError = undefined;
    this.payCopied = false;
  }

  async handlePayCreate() {
    this.payLoading = true;
    this.payError = undefined;
    this.payCopied = false;
    try {
      this.payResult = await createInvoiceLink({
        invoiceId: this.payInvoiceId
      });
    } catch (e) {
      this.payResult = undefined;
      this.payError = e?.body?.message || "Could not create the payment link.";
    } finally {
      this.payLoading = false;
    }
  }

  async handlePayCopy() {
    try {
      await navigator.clipboard.writeText(this.payResult.url);
      this.payCopied = true;
    } catch {
      this.payError =
        "Copy the link from the box (your browser blocked automatic copying).";
    }
  }

  // ---------------------------------------------------------------- KPIs

  get kpis() {
    return (this.data?.kpis || []).map((k) => ({
      ...k,
      display: this.formatValue(k.value, k.format),
      className: `kpi ${TONE_CLASS[k.tone] || TONE_CLASS.neutral}`,
      ariaLabel: `${k.label}: ${this.formatValue(k.value, k.format)}. ${k.sub || ""}. Open the list.`,
      notClickable: !k.objectApiName
    }));
  }

  formatValue(value, format) {
    const n = Number(value) || 0;
    try {
      switch (format) {
        case "money":
          return new Intl.NumberFormat(undefined, {
            style: "currency",
            currency: this.currencyCode,
            notation: Math.abs(n) >= 100000 ? "compact" : "standard",
            maximumFractionDigits: Math.abs(n) >= 1000 ? 0 : 2
          }).format(n);
        case "percent":
          return `${new Intl.NumberFormat(undefined, { maximumFractionDigits: n < 10 ? 1 : 0 }).format(n)}%`;
        case "hours":
          return `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(n)} h`;
        default:
          return new Intl.NumberFormat(undefined, {
            maximumFractionDigits: 1
          }).format(n);
      }
    } catch {
      return String(n);
    }
  }

  handleKpiClick(evt) {
    const k = (this.data?.kpis || []).find(
      (x) => x.key === evt.currentTarget.dataset.key
    );
    if (k?.objectApiName) {
      this.openList(k.objectApiName, k.listView);
    }
  }

  // ---------------------------------------------------------------- charts

  get charts() {
    return (this.data?.charts || []).map((c) => ({ ...c, cardKey: c.key }));
  }

  // ---------------------------------------------------------------- work queues

  get sectionTabs() {
    return (this.data?.sections || []).map((s) => ({
      key: s.key,
      title: s.title,
      total: s.total,
      selected: s.key === this.activeSection ? "true" : "false",
      tabIndex: s.key === this.activeSection ? "0" : "-1",
      className: `queue-tab${s.key === this.activeSection ? " queue-tab_active" : ""}${s.total ? "" : " queue-tab_empty"}`,
      countClass: `queue-count${s.total ? " queue-count_hot" : ""}`
    }));
  }

  get activeQueue() {
    const s = (this.data?.sections || []).find(
      (x) => x.key === this.activeSection
    );
    if (!s) return null;
    return {
      ...s,
      hasItems: s.items.length > 0,
      more:
        s.total > s.items.length
          ? `View all ${s.total}`
          : s.total
            ? "View list"
            : null,
      items: s.items.map((i, idx) => this.decorateItem(i, `${s.key}-${idx}`))
    };
  }

  decorateItem(i, key) {
    return {
      ...i,
      key,
      badgeClass: `badge ${TONE_CLASS[i.tone] || TONE_CLASS.neutral}`,
      amountLabel:
        i.amount != null ? this.formatValue(i.amount, "money") : null,
      hasDate: !!(i.whenDt || i.whenDate),
      isDateTime: !!i.whenDt
    };
  }

  handleTab(evt) {
    this.activeSection = evt.currentTarget.dataset.key;
  }

  handleTabKey(evt) {
    const keys = (this.data?.sections || []).map((s) => s.key);
    const i = keys.indexOf(this.activeSection);
    if (evt.key === "ArrowRight" || evt.key === "ArrowLeft") {
      evt.preventDefault();
      const next =
        evt.key === "ArrowRight"
          ? (i + 1) % keys.length
          : (i - 1 + keys.length) % keys.length;
      this.activeSection = keys[next];
      Promise.resolve().then(() => {
        const btn = this.template.querySelector(
          `button[data-key="${keys[next]}"]`
        );
        if (btn) btn.focus();
      });
    }
  }

  handleViewAll() {
    const s = (this.data?.sections || []).find(
      (x) => x.key === this.activeSection
    );
    if (s?.objectApiName) {
      this.openList(s.objectApiName, s.listView);
    }
  }

  openRecord(evt) {
    const recordId = evt.currentTarget.dataset.id;
    if (recordId) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: { recordId, actionName: "view" }
      });
    }
  }

  // ---------------------------------------------------------------- agenda

  get agenda() {
    return (this.data?.agenda || []).map((i, idx) =>
      this.decorateItem(i, `ag-${idx}`)
    );
  }

  get hasAgenda() {
    return this.agenda.length > 0;
  }

  get lowerClass() {
    return this.agendaVisible ? "lower" : "lower lower_single";
  }

  get agendaTitle() {
    switch (this.module) {
      case "Hotel":
        return "Today at the front desk";
      case "Practice":
        return "Today's appointments";
      case "Property":
        return "Next 7 days";
      case "Projects":
        return "Due in the next 14 days";
      default:
        return "Starting today";
    }
  }
}
