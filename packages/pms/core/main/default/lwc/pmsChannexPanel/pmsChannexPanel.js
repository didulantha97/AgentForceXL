import { LightningElement, api } from "lwc";
import getState from "@salesforce/apex/PMS_ChannexController.getState";
import pushNowApex from "@salesforce/apex/PMS_ChannexController.pushNow";
import syncNowApex from "@salesforce/apex/PMS_ChannexController.syncNow";

const STATUS_CLASS = {
  Success: "slds-badge slds-theme_success",
  Warning: "slds-badge slds-theme_warning",
  Error: "slds-badge slds-theme_error"
};

export default class PmsChannexPanel extends LightningElement {
  @api recordId;
  s;
  busy = false;
  error;
  result;

  connectedCallback() {
    this.load();
  }

  get statusLabel() {
    if (!this.s) return "";
    if (!this.s.propertyId) return "Not connected";
    return this.s.enabled
      ? "Connected, syncing every 15 minutes"
      : "Connected, sync switched off";
  }

  get statusClass() {
    if (!this.s || !this.s.propertyId) return "slds-badge";
    return this.s.enabled
      ? "slds-badge slds-theme_success"
      : "slds-badge slds-theme_warning";
  }

  get hasProblems() {
    return this.s && this.s.problems && this.s.problems.length > 0;
  }

  get problemRows() {
    return (this.s?.problems || []).map((text, i) => ({ key: i, text }));
  }

  get hasLogs() {
    return this.s && this.s.logs && this.s.logs.length > 0;
  }

  get logRows() {
    return (this.s?.logs || []).map((l) => ({
      ...l,
      cls: STATUS_CLASS[l.status] || "slds-badge",
      bookingUrl: l.bookingId ? "/" + l.bookingId : null
    }));
  }

  async run(fn) {
    this.busy = true;
    this.error = undefined;
    try {
      await fn();
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) ||
        (e && e.message) ||
        "Something went wrong.";
    } finally {
      this.busy = false;
    }
  }

  async load() {
    await this.run(async () => {
      this.s = await getState({ siteId: this.recordId });
    });
  }

  async pushNow() {
    await this.run(async () => {
      this.result = await pushNowApex({ siteId: this.recordId });
    });
    await this.load();
  }

  async syncNow() {
    await this.run(async () => {
      await syncNowApex();
      this.result =
        "Sync queued. Bookings appear in the log within a minute or two.";
    });
  }
}
