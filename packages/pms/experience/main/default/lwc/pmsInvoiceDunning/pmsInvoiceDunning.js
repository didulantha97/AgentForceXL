import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getState from "@salesforce/apex/PMS_DunningController.getState";
import sendNextApex from "@salesforce/apex/PMS_DunningController.sendNext";
import offerPlanApex from "@salesforce/apex/PMS_DunningController.offerPlan";
import pauseApex from "@salesforce/apex/PMS_DunningController.pause";
import resumeApex from "@salesforce/apex/PMS_DunningController.resume";

const STAGE_CLASS = {
  "Reminder 1": "slds-badge slds-theme_warning",
  "Reminder 2": "slds-badge slds-theme_warning",
  "Plan Offered": "slds-badge",
  "Payment Plan": "slds-badge slds-theme_success",
  Collections: "slds-badge slds-theme_error"
};

export default class PmsInvoiceDunning extends LightningElement {
  @api recordId;
  s;
  error;
  busy = false;
  showPause = false;
  showPlan = false;
  pauseReason = "";
  instalments = 3;

  connectedCallback() {
    this.load();
  }

  get stageLabel() {
    if (this.s?.stage) return this.s.stage;
    return this.s?.closed ? "Paid / closed" : "No reminders yet";
  }

  get stageClass() {
    return STAGE_CLASS[this.s?.stage] || "slds-badge slds-badge_lightest";
  }

  get noPolicy() {
    return this.s && !this.s.hasPolicy && !this.s.closed;
  }

  get hasEvents() {
    return this.s?.events?.length > 0;
  }

  get canPause() {
    return this.s && !this.s.closed;
  }

  get sendLabel() {
    return `Send ${this.s?.nextStep || "next step"} now`;
  }

  async load() {
    await this.run(async () => {
      this.s = await getState({ invoiceId: this.recordId });
      this.instalments = this.s?.defaultInstalments || 3;
    });
  }

  async run(fn, done) {
    this.busy = true;
    this.error = undefined;
    try {
      await fn();
      if (done) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Done",
            message: done,
            variant: "success"
          })
        );
      }
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) ||
        (e && e.message) ||
        "Something went wrong.";
    } finally {
      this.busy = false;
    }
  }

  refreshRecord() {
    notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
  }

  async sendNext() {
    const ok = await LightningConfirm.open({
      label: `Send ${this.s.nextStep} now?`,
      message:
        "The letter is emailed straight away, and any fee or interest for this step is added to the invoice.",
      theme: "warning"
    });
    if (!ok) return;
    await this.run(async () => {
      this.s = await sendNextApex({ invoiceId: this.recordId });
      this.refreshRecord();
    }, "Step sent.");
  }

  togglePlan() {
    this.showPlan = !this.showPlan;
    this.showPause = false;
  }

  onInstalments(e) {
    this.instalments = e.detail.value;
  }

  async doPlan() {
    const n = parseInt(this.instalments, 10);
    if (!(n >= 2 && n <= 24)) {
      this.error = "Choose between 2 and 24 instalments.";
      return;
    }
    await this.run(async () => {
      this.s = await offerPlanApex({
        invoiceId: this.recordId,
        instalments: n
      });
      this.showPlan = false;
      this.refreshRecord();
    }, "Payment plan offered.");
  }

  togglePause() {
    this.showPause = !this.showPause;
    this.showPlan = false;
  }

  onPauseReason(e) {
    this.pauseReason = e.detail.value;
  }

  async doPause() {
    await this.run(async () => {
      this.s = await pauseApex({
        invoiceId: this.recordId,
        reason: this.pauseReason
      });
      this.showPause = false;
      this.refreshRecord();
    }, "Dunning paused.");
  }

  async doResume() {
    await this.run(async () => {
      this.s = await resumeApex({ invoiceId: this.recordId });
      this.refreshRecord();
    }, "Dunning resumed.");
  }
}
