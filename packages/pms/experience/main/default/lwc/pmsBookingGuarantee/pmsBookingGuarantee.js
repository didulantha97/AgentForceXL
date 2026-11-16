import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getState from "@salesforce/apex/PMS_GuaranteeController.getState";
import sendLinkApex from "@salesforce/apex/PMS_GuaranteeController.sendLink";
import chargeDepositApex from "@salesforce/apex/PMS_GuaranteeController.chargeDeposit";
import placeHoldApex from "@salesforce/apex/PMS_GuaranteeController.placeHold";
import captureHoldApex from "@salesforce/apex/PMS_GuaranteeController.captureHold";
import applyPolicyApex from "@salesforce/apex/PMS_GuaranteeController.applyPolicyNow";

const STATUS_CLASS = {
  "Card Saved": "slds-badge slds-theme_success",
  "Deposit Paid": "slds-badge slds-theme_success",
  "Hold Placed": "slds-badge slds-theme_success",
  Settled: "slds-badge slds-badge_inverse",
  "Awaiting Card": "slds-badge slds-theme_warning",
  "Action Needed": "slds-badge slds-theme_error"
};

export default class PmsBookingGuarantee extends LightningElement {
  @api recordId;
  s;
  error;
  busy = false;
  linkUrl;
  showCapture = false;
  captureAmount;

  connectedCallback() {
    this.load();
  }

  get statusClass() {
    return (
      (STATUS_CLASS[this.s?.guaranteeStatus] || "slds-badge") +
      " slds-m-left_x-small"
    );
  }

  get cardLabel() {
    const s = this.s;
    if (!s?.cardLast4) {
      return "Card saved (details loading)";
    }
    return `${s.cardBrand || "Card"} •••• ${s.cardLast4}${s.cardExpiry ? " · exp " + s.cardExpiry : ""}`;
  }

  get amountLabel() {
    const m = this.s?.method;
    if (m === "Pre-authorisation") return "Hold amount";
    if (m === "Prepaid") return "To prepay";
    if (m === "Deposit") return "Deposit";
    return "Charged now";
  }

  get hasDepositPaid() {
    return this.s?.depositPaid > 0;
  }

  get freeLabel() {
    const h = this.s?.freeHours;
    return h
      ? `Free up to ${h} h before arrival`
      : "No free cancellation window";
  }

  get autoLabel() {
    return this.s?.autoCharge
      ? "; charged automatically"
      : "; posted to an invoice only";
  }

  get sendLabel() {
    return this.s?.linkSentAt ? "Resend card link" : "Email card link";
  }

  async load() {
    await this.run(async () => {
      this.s = await getState({ bookingId: this.recordId });
    });
  }

  async run(fn, successMessage) {
    this.busy = true;
    this.error = undefined;
    try {
      await fn();
      if (successMessage) {
        this.toast("Done", successMessage, "success");
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

  async afterChange(state) {
    if (state) {
      this.s = state;
    } else {
      this.s = await getState({ bookingId: this.recordId });
    }
    notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    if (this.s?.message && this.s.guaranteeStatus === "Action Needed") {
      this.toast("Check the booking", this.s.message, "warning");
    }
  }

  async sendLink() {
    const to = this.s?.contactEmail;
    if (!to) {
      this.error =
        "The guest has no email address. Use Copy link and send it another way.";
      return;
    }
    await this.run(async () => {
      const r = await sendLinkApex({ bookingId: this.recordId, email: true });
      this.linkUrl = r.url;
      await this.afterChange();
    }, `Link emailed to ${to}.`);
  }

  async getLink() {
    await this.run(async () => {
      const r = await sendLinkApex({ bookingId: this.recordId, email: false });
      this.linkUrl = r.url;
      await this.afterChange();
    });
  }

  async copyLink() {
    try {
      await navigator.clipboard.writeText(this.linkUrl);
      this.toast("Copied", "The card link is on your clipboard.", "success");
    } catch {
      this.toast(
        "Copy the link by hand",
        "Your browser blocked clipboard access.",
        "info"
      );
    }
  }

  async chargeDeposit() {
    const ok = await LightningConfirm.open({
      label: "Charge the deposit?",
      message: `This charges the guest's saved card now (${this.formatMoney(this.s.guaranteeAmount)}).`,
      theme: "warning"
    });
    if (!ok) return;
    await this.run(async () => {
      await this.afterChange(
        await chargeDepositApex({ bookingId: this.recordId })
      );
    });
  }

  async placeHold() {
    const ok = await LightningConfirm.open({
      label: "Place a hold on the card?",
      message: `Reserves ${this.formatMoney(this.s.guaranteeAmount)} on the card. Holds expire after 4 to 7 days depending on the card network.`,
      theme: "warning"
    });
    if (!ok) return;
    await this.run(async () => {
      await this.afterChange(await placeHoldApex({ bookingId: this.recordId }));
    });
  }

  toggleCapture() {
    this.showCapture = !this.showCapture;
    this.captureAmount = this.s?.holdAmount;
  }

  onCaptureAmount(e) {
    this.captureAmount = e.detail.value;
  }

  async doCapture() {
    const amount =
      this.captureAmount === "" || this.captureAmount == null
        ? 0
        : Number(this.captureAmount);
    const ok = await LightningConfirm.open({
      label: amount > 0 ? "Capture from the hold?" : "Release the hold?",
      message:
        amount > 0
          ? `Captures ${this.formatMoney(amount)} and releases the rest of the hold.`
          : "Releases the whole hold. Nothing is charged.",
      theme: "warning"
    });
    if (!ok) return;
    await this.run(async () => {
      await this.afterChange(
        await captureHoldApex({ bookingId: this.recordId, amount })
      );
      this.showCapture = false;
    });
  }

  async applyPolicy() {
    const ok = await LightningConfirm.open({
      label: "Apply the cancellation policy?",
      message:
        "Posts the fee on an invoice and, if the policy says so, charges the saved card or captures the hold.",
      theme: "warning"
    });
    if (!ok) return;
    await this.run(async () => {
      await this.afterChange(
        await applyPolicyApex({ bookingId: this.recordId })
      );
    });
  }

  formatMoney(v) {
    try {
      return new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: this.s?.currencyCode || "SEK"
      }).format(v || 0);
    } catch {
      return `${v} ${this.s?.currencyCode || ""}`;
    }
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
