import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import getGuest360 from "@salesforce/apex/PMS_Guest360Controller.getGuest360";
import { errorMessage } from "c/pmsDateUtils";

const STATUS_CLASS = {
  Inquiry: "",
  Tentative: "slds-theme_warning",
  Confirmed: "slds-theme_success",
  Active: "slds-theme_success",
  Completed: "",
  Cancelled: "slds-theme_error",
  "No Show": "slds-theme_error"
};

/** Guest 360: read-only guest summary for a Contact record or app page. */
export default class PmsGuest360 extends NavigationMixin(LightningElement) {
  @api recordId;

  data;
  error;
  loaded = false;
  wiredResult;

  _lastRecordId;

  renderedCallback() {
    this.resetOnRecordChange();
  }

  resetOnRecordChange() {
    if (this._lastRecordId !== this.recordId) {
      this._lastRecordId = this.recordId;
      this.data = undefined;
      this.error = undefined;
      this.loaded = false;
    }
  }

  @wire(getGuest360, { contactId: "$recordId" })
  wiredGuest(result) {
    this.resetOnRecordChange();
    this.wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.data = data;
      this.error = undefined;
      this.loaded = true;
    } else if (error) {
      this.data = undefined;
      this.error = errorMessage(error);
      this.loaded = true;
    }
  }

  get hasRecord() {
    return !!this.recordId;
  }
  get showLoading() {
    return this.hasRecord && !this.loaded;
  }
  get showNoRecord() {
    return !this.hasRecord;
  }
  get showContent() {
    return !!this.data;
  }
  get identity() {
    return this.data?.identity || {};
  }
  get hasVip() {
    return !!this.identity.vipLevel;
  }
  get vipLabel() {
    return `VIP: ${this.identity.vipLevel}`;
  }
  get idVerified() {
    return this.identity.idVerified === true;
  }
  get idIcon() {
    return this.idVerified ? "utility:success" : "utility:warning";
  }
  get idText() {
    return this.idVerified ? "ID verified" : "ID not verified";
  }

  // ---- stats ----
  get stats() {
    return this.data?.stats?.accessible ? this.data.stats : null;
  }
  get showStats() {
    return !!this.stats;
  }
  get statsRefreshed() {
    return this.stats?.refreshedOn
      ? new Date(this.stats.refreshedOn).getTime()
      : null;
  }
  get kpis() {
    const s = this.stats;
    if (!s) {
      return [];
    }
    return [
      { key: "stays", label: "Total stays", number: s.totalStays },
      { key: "nights", label: "Lifetime nights", number: s.lifetimeNights },
      { key: "room", label: "Room revenue", currency: s.roomRevenue },
      { key: "extras", label: "Extras revenue", currency: s.extrasRevenue },
      { key: "first", label: "First stay", date: s.firstStay },
      { key: "last", label: "Last stay", date: s.lastStay },
      { key: "next", label: "Next arrival", date: s.nextArrival }
    ].map((k) => ({
      ...k,
      isNumber: "number" in k && k.number != null,
      isCurrency: "currency" in k && k.currency != null,
      isDate: "date" in k && !!k.date,
      isEmpty: !(
        ("number" in k && k.number != null) ||
        ("currency" in k && k.currency != null) ||
        ("date" in k && k.date)
      )
    }));
  }

  // ---- stays ----
  decorateStays(items) {
    return (items || []).map((s) => ({
      ...s,
      key: s.bookingId,
      badgeClass: `slds-badge ${STATUS_CLASS[s.status] || ""}`.trim(),
      hasBalance: !s.viaParty && s.balanceDue != null && s.balanceDue > 0,
      hasBalanceValue: !s.viaParty && s.balanceDue != null,
      showRequests: !s.viaParty && !!s.specialRequests
    }));
  }
  get upcomingAccessible() {
    return !!this.data?.upcomingStays?.accessible;
  }
  get pastAccessible() {
    return !!this.data?.pastStays?.accessible;
  }
  get upcoming() {
    return this.upcomingAccessible
      ? this.decorateStays(this.data?.upcomingStays?.items)
      : [];
  }
  get past() {
    return this.pastAccessible
      ? this.decorateStays(this.data?.pastStays?.items)
      : [];
  }
  get noUpcoming() {
    return this.upcoming.length === 0;
  }
  get noPast() {
    return this.past.length === 0;
  }
  get upcomingLabel() {
    return `Upcoming stays (${this.upcoming.length})`;
  }
  get pastLabel() {
    return `Past stays (${this.past.length})`;
  }

  // ---- preferences ----
  get prefsAccessible() {
    return !!this.data?.preferences?.accessible;
  }
  get highlights() {
    const i = this.identity;
    const out = [];
    if (i.dietary) {
      out.push({
        key: "dietary",
        icon: "utility:food_and_drink",
        label: "Dietary",
        value: i.dietary
      });
    }
    if (i.accessibilityNeeds) {
      out.push({
        key: "access",
        icon: "utility:user",
        label: "Accessibility needs",
        value: i.accessibilityNeeds
      });
    }
    return out;
  }
  get hasHighlights() {
    return this.highlights.length > 0;
  }
  get prefGroups() {
    if (!this.prefsAccessible) {
      return [];
    }
    const groups = new Map();
    (this.data?.preferences?.items || []).forEach((p) => {
      const cat = p.category || "Other";
      if (!groups.has(cat)) {
        groups.set(cat, []);
      }
      groups.get(cat).push({ ...p, key: p.preferenceId });
    });
    const priority = (c) => (c === "Food & Drink" ? 0 : 1);
    return Array.from(groups.entries())
      .map(([category, items]) => ({
        category,
        key: category,
        items,
        priority: priority(category),
        icon: category === "Food & Drink" ? "utility:food_and_drink" : null
      }))
      .sort((a, b) => a.priority - b.priority);
  }
  get noPrefs() {
    return !this.hasHighlights && this.prefGroups.length === 0;
  }
  get prefsLabel() {
    return "Preferences";
  }

  // ---- service ----
  get serviceAccessible() {
    return !!this.data?.service?.accessible;
  }
  get cases() {
    if (!this.serviceAccessible) {
      return [];
    }
    return (this.data?.service?.items || []).map((c) => ({
      ...c,
      key: c.caseId,
      statusText: c.isClosed ? `${c.status} (closed)` : `${c.status} (open)`,
      badgeClass: `slds-badge ${c.isClosed ? "" : "slds-theme_warning"}`.trim()
    }));
  }
  get noCases() {
    return this.cases.length === 0;
  }
  get serviceLabel() {
    return `Service (${this.cases.length})`;
  }

  // ---- consent ----
  get consent() {
    return this.data?.consent?.accessible ? this.data.consent : null;
  }
  get showConsent() {
    return !!this.consent;
  }
  get marketingText() {
    const c = this.consent;
    if (!c || c.marketingConsent == null) {
      return "Not recorded";
    }
    return c.marketingConsent ? "Opted in" : "Not opted in";
  }
  get marketingIcon() {
    const c = this.consent;
    return c && c.marketingConsent ? "utility:success" : "utility:info";
  }
  get doNotContact() {
    return !!this.consent?.doNotContact;
  }
  get formShown() {
    return !!this.consent?.formAccessible;
  }
  get hasForm() {
    return this.formShown && this.consent?.gdprFormDate != null;
  }
  get formText() {
    return this.consent?.gdprFormConsentGiven
      ? "Consent given"
      : "Consent not given";
  }
  get consentDateValue() {
    return this.consent?.consentDate
      ? new Date(this.consent.consentDate).getTime()
      : null;
  }
  get formDateValue() {
    return this.hasForm ? new Date(this.consent?.gdprFormDate).getTime() : null;
  }

  // ---- actions ----
  handleRefresh() {
    if (!this.hasRecord || !this.wiredResult) {
      return;
    }
    this.loaded = false;
    Promise.resolve(refreshApex(this.wiredResult)).finally(() => {
      this.loaded = true;
    });
  }
  handleOpen(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }
}
