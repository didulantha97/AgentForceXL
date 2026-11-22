import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getStatus from "@salesforce/apex/PMS_DemoDataController.getStatus";
import load from "@salesforce/apex/PMS_DemoDataController.load";
import reset from "@salesforce/apex/PMS_DemoDataController.reset";

const STATE_LABELS = {
  NONE: "Not loaded",
  RUNNING: "Loading",
  DONE: "Loaded",
  FAILED: "Failed",
  RESETTING: "Removing"
};
const STATE_BADGES = {
  DONE: "slds-theme_success",
  RUNNING: "slds-theme_warning",
  RESETTING: "slds-theme_warning",
  FAILED: "slds-theme_error"
};

/**
 * Admin card for the demo data packs. The server decides whether to show anything: in production, or for a
 * user who is not an admin, getStatus returns allowed = false and this component renders nothing. In a Developer
 * Edition or trial org that has not opted in (optInRequired) an admin sees the card with the reason instead.
 */
export default class PmsDemoDataCard extends LightningElement {
  @api cardTitle = "Demo data";
  @api refreshSeconds = 10;

  status = { allowed: false, packs: [], counts: [], total: 0 };
  lastMessage;
  working = false;
  confirmKey;
  _timer;

  connectedCallback() {
    this.refresh();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  get visible() {
    return !!(
      this.status &&
      (this.status.allowed || this.status.optInRequired)
    );
  }

  get intro() {
    return "Fill this org with realistic Swedish sample data (SEK) for demos and testing. Every record is tracked, so Reset removes exactly what was loaded.";
  }

  get hasCounts() {
    return !!(this.status.counts && this.status.counts.length);
  }

  get rows() {
    const canRun = !!this.status.canRun;
    const busy = !!this.status.busy || this.working;
    return (this.status.packs || []).map((p) => {
      const state = p.state || "NONE";
      return {
        key: p.key,
        label: p.label,
        description: p.description,
        message: p.message,
        stateLabel: STATE_LABELS[state] || state,
        badgeClass: STATE_BADGES[state] || "",
        recordsLabel: p.records ? `${p.records} records` : "No records",
        loadDisabled: !canRun || busy || state !== "NONE",
        resetDisabled: !canRun || busy || (state === "NONE" && !p.records),
        confirming: this.confirmKey === p.key
      };
    });
  }

  async refresh() {
    try {
      this.status = await getStatus();
      this.syncPolling();
    } catch {
      this.status = { allowed: false, packs: [], counts: [], total: 0 };
      this.stopPolling();
    }
  }

  syncPolling() {
    if (this.status && this.status.busy) {
      if (!this._timer) {
        const ms = Math.max(2, Number(this.refreshSeconds) || 10) * 1000;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = setInterval(() => this.refresh(), ms);
      }
    } else {
      this.stopPolling();
    }
  }

  stopPolling() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = undefined;
    }
  }

  handleRefresh() {
    this.refresh();
  }

  async run(action, pack) {
    this.working = true;
    this.confirmKey = undefined;
    try {
      this.status = await action({ pack });
      this.lastMessage = this.status.message;
      const refused =
        !this.lastMessage ||
        /^(Refused|Unknown|Another|Nothing|Pack ".*" (is|did)|The baseline)/.test(
          this.lastMessage
        );
      this.dispatchEvent(
        new ShowToastEvent({
          title: refused ? "Nothing started" : "Started",
          message: this.lastMessage,
          variant: refused ? "warning" : "success"
        })
      );
      this.syncPolling();
    } catch (error) {
      const message = this.reduceError(error);
      this.lastMessage = message;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Demo data",
          message,
          variant: "error"
        })
      );
    } finally {
      this.working = false;
    }
  }

  handleLoad(event) {
    return this.run(load, event.target.dataset.pack);
  }

  handleAskReset(event) {
    this.confirmKey = event.target.dataset.pack;
  }

  handleCancelReset() {
    this.confirmKey = undefined;
  }

  handleConfirmReset(event) {
    return this.run(reset, event.target.dataset.pack);
  }

  reduceError(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return (error && error.message) || "Something went wrong.";
  }
}
