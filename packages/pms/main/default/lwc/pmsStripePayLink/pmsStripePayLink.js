import { LightningElement, api } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
import createInvoiceLink from "@salesforce/apex/PMS_StripeCheckout.createInvoiceLink";

export default class PmsStripePayLink extends LightningElement {
  @api recordId;
  result;
  error;
  loading = false;
  copied = false;

  get hasResult() {
    return !!this.result;
  }

  get createLabel() {
    return this.result ? "Create new link" : "Create link";
  }

  get expiresLabel() {
    if (!this.result || !this.result.expiresAt) {
      return "";
    }
    return new Date(this.result.expiresAt).toLocaleString();
  }

  async handleCreate() {
    this.loading = true;
    this.error = undefined;
    this.copied = false;
    try {
      this.result = await createInvoiceLink({ invoiceId: this.recordId });
    } catch (e) {
      this.result = undefined;
      this.error =
        (e && e.body && e.body.message) || "Could not create the payment link.";
    } finally {
      this.loading = false;
    }
  }

  async handleCopy() {
    try {
      await navigator.clipboard.writeText(this.result.url);
      this.copied = true;
    } catch {
      const input = this.template.querySelector("lightning-input");
      if (input) {
        input.focus();
      }
      this.error =
        "Copy the link from the box above (your browser blocked automatic copying).";
    }
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
