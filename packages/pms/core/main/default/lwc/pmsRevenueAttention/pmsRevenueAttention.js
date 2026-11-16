import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getAttention from "@salesforce/apex/PMS_RevenueHomeController.getAttention";
import reportIds from "@salesforce/apex/PMS_RevenueHomeController.reportIds";

// Report ids are resolved at runtime by PMS_RevenueHomeController.reportIds() (item key => report id),
// so nothing org-specific is hard-coded here. A tile without a visible report gets no "Open report" link.

export default class PmsRevenueAttention extends LightningElement {
  @api module = "Admin";
  data;
  error;
  openKey;
  wired;
  reports = {};

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

  @wire(reportIds)
  loadReports({ data }) {
    if (data) {
      this.reports = data;
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
        reportUrl: this.reports[i.key]
          ? `/lightning/r/Report/${this.reports[i.key]}/view`
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
