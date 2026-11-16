import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getAttention from "@salesforce/apex/PMS_RevenueHomeController.getAttention";

// Reports in the PMS Reports folder (codeterriers4). Report ids differ per org: update these when the
// package is installed elsewhere, or set them to null to hide the "Open report" links.
const REPORTS = {
  reminders: "00OkO000000LJFlUAO", // PMS Invoices by Reminder Stage
  cards: "00OkO000000LHNjUAO", // PMS Bookings by Card and Deposit Status
  rent: "00OkO000000LJHNUA4" // PMS Rent Adjustments
};

export default class PmsRevenueAttention extends LightningElement {
  @api module = "Admin";
  data;
  error;
  openKey;
  wired;

  @wire(getAttention, { module: "$module" })
  load(result) {
    this.wired = result;
    if (result.data) {
      this.data = result.data;
      this.error = undefined;
    } else if (result.error) {
      this.error = result.error.body
        ? result.error.body.message
        : "Could not load revenue items.";
    }
  }

  get loading() {
    return !this.data && !this.error;
  }

  get items() {
    if (!this.data) {
      return [];
    }
    return this.data.items
      .filter((i) => i.count > 0)
      .map((i) => ({
        ...i,
        countText: i.more ? `${i.count}+` : String(i.count),
        open: i.key === this.openKey,
        tileClass:
          `tile tile-${i.severity}` +
          (i.key === this.openKey ? " tile-open" : ""),
        reportUrl: REPORTS[i.key]
          ? `/lightning/r/Report/${REPORTS[i.key]}/view`
          : null,
        extra: i.count > i.rows.length ? i.count - i.rows.length : 0
      }));
  }

  get allClear() {
    return this.data && this.items.length === 0;
  }

  get warnings() {
    return this.data && this.data.warnings && this.data.warnings.length
      ? this.data.warnings.join(" | ")
      : null;
  }

  toggle(event) {
    const key = event.currentTarget.dataset.key;
    this.openKey = this.openKey === key ? null : key;
  }

  refresh() {
    return refreshApex(this.wired);
  }
}
