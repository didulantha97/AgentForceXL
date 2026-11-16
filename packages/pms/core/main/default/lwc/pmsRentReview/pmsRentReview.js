import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import loadApex from "@salesforce/apex/PMS_RentReviewController.load";
import saveIndexApex from "@salesforce/apex/PMS_RentReviewController.saveIndexValue";
import prepareIndexApex from "@salesforce/apex/PMS_RentReviewController.prepareIndex";
import prepareNegotiatedApex from "@salesforce/apex/PMS_RentReviewController.prepareNegotiated";
import approveApex from "@salesforce/apex/PMS_RentReviewController.approve";
import sendNoticesApex from "@salesforce/apex/PMS_RentReviewController.sendNotices";
import cancelApex from "@salesforce/apex/PMS_RentReviewController.cancel";
import updateNewRentApex from "@salesforce/apex/PMS_RentReviewController.updateNewRent";

const MONEY = {
  type: "currency",
  typeAttributes: { currencyCode: "SEK" },
  cellAttributes: { alignment: "right" }
};

export default class PmsRentReview extends LightningElement {
  year =
    new Date().getMonth() >= 9
      ? new Date().getFullYear() + 1
      : new Date().getFullYear();
  rows = [];
  indexValues = [];
  sites = [];
  selected = [];
  draftValues = [];
  messages = [];
  busy = false;
  error;

  indexSite = "";
  negSite = "";
  negPercent;
  negDate;
  negNote;

  ivSeries = "KPI 1980=100";
  ivYear = new Date().getFullYear();
  ivMonth = 10;
  ivValue;
  ivSource = "SCB";

  seriesOptions = [
    { label: "KPI 1980=100", value: "KPI 1980=100" },
    { label: "KPI 2020=100", value: "KPI 2020=100" }
  ];

  columns = [
    { label: "Lease", fieldName: "lease" },
    { label: "Tenant", fieldName: "tenant" },
    { label: "Premises", fieldName: "premises" },
    { label: "Kind", fieldName: "kind", initialWidth: 110 },
    { label: "Status", fieldName: "status", initialWidth: 120 },
    {
      label: "From",
      fieldName: "effectiveDate",
      type: "date-local",
      initialWidth: 110
    },
    { label: "Old rent", fieldName: "oldRent", ...MONEY },
    { label: "New rent", fieldName: "newRent", editable: true, ...MONEY },
    {
      label: "Change",
      fieldName: "changePct",
      type: "percent",
      typeAttributes: { maximumFractionDigits: 2 },
      initialWidth: 100
    },
    { label: "Check", fieldName: "warning", wrapText: true }
  ];

  indexColumns = [
    { label: "Series", fieldName: "series" },
    {
      label: "Year",
      fieldName: "year",
      type: "number",
      typeAttributes: { useGrouping: false }
    },
    { label: "Month", fieldName: "month", type: "number" },
    {
      label: "Value",
      fieldName: "value",
      type: "number",
      typeAttributes: { minimumFractionDigits: 2 }
    },
    { label: "Source", fieldName: "source" }
  ];

  connectedCallback() {
    this.load();
  }

  get prevYear() {
    return Number(this.year) - 1;
  }

  get noSelection() {
    return this.busy || this.selected.length === 0;
  }

  get noRows() {
    return !this.busy && this.rows.length === 0;
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
      const d = await loadApex({ year: Number(this.year) });
      this.rows = d.rows.map((r) => ({
        ...r,
        changePct: r.changePercent == null ? null : r.changePercent / 100
      }));
      this.indexValues = d.indexValues;
      this.sites = d.sites;
      this.selected = [];
      this.draftValues = [];
    });
  }

  showMessages(lines) {
    this.messages = (lines || []).map((text, i) => ({ key: i, text }));
  }

  toast(message) {
    this.dispatchEvent(
      new ShowToastEvent({ title: "Rent review", message, variant: "success" })
    );
  }

  onYear(e) {
    this.year = e.detail.value;
    this.load();
  }
  onIndexSite(e) {
    this.indexSite = e.detail.value;
  }
  onNegSite(e) {
    this.negSite = e.detail.value;
  }
  onNegPercent(e) {
    this.negPercent = e.detail.value;
  }
  onNegDate(e) {
    this.negDate = e.detail.value;
  }
  onNegNote(e) {
    this.negNote = e.detail.value;
  }
  onIvSeries(e) {
    this.ivSeries = e.detail.value;
  }
  onIvYear(e) {
    this.ivYear = e.detail.value;
  }
  onIvMonth(e) {
    this.ivMonth = e.detail.value;
  }
  onIvValue(e) {
    this.ivValue = e.detail.value;
  }
  onIvSource(e) {
    this.ivSource = e.detail.value;
  }

  onSelect(e) {
    this.selected = e.detail.selectedRows.map((r) => r.id);
  }

  async prepareIndex() {
    await this.run(async () => {
      const r = await prepareIndexApex({
        year: Number(this.year),
        siteId: this.indexSite
      });
      this.showMessages([
        `${r.created} index adjustment(s) drafted.`,
        ...r.messages
      ]);
    });
    await this.load();
  }

  async prepareNegotiated() {
    if (
      this.negPercent === undefined ||
      this.negPercent === "" ||
      !this.negDate
    ) {
      this.error = "Enter the agreed % and the date it applies from.";
      return;
    }
    await this.run(async () => {
      const r = await prepareNegotiatedApex({
        siteId: this.negSite,
        percent: Number(this.negPercent),
        effectiveDate: this.negDate,
        note: this.negNote
      });
      this.showMessages([
        `${r.created} negotiated adjustment(s) drafted.`,
        ...r.messages
      ]);
    });
    if (
      this.negDate &&
      String(this.negDate).substring(0, 4) !== String(this.year)
    ) {
      this.year = Number(String(this.negDate).substring(0, 4));
    }
    await this.load();
  }

  async approve() {
    await this.run(async () => {
      const n = await approveApex({ ids: this.selected });
      this.toast(`${n} adjustment(s) approved.`);
    });
    await this.load();
  }

  async sendNotices() {
    const ok = await LightningConfirm.open({
      label: "Send notices?",
      message:
        "Approved adjustments among the selected rows are emailed to the tenants now.",
      theme: "warning"
    });
    if (!ok) return;
    await this.run(async () => {
      const lines = await sendNoticesApex({ ids: this.selected });
      this.showMessages(
        lines.length
          ? lines
          : ["Nothing sent: only approved adjustments get a notice."]
      );
    });
    await this.load();
  }

  async cancel() {
    const ok = await LightningConfirm.open({
      label: "Cancel the selected adjustments?",
      message: "Applied adjustments are not affected."
    });
    if (!ok) return;
    await this.run(async () => {
      const n = await cancelApex({ ids: this.selected });
      this.toast(`${n} adjustment(s) cancelled.`);
    });
    await this.load();
  }

  async onSave(e) {
    const drafts = e.detail.draftValues;
    await this.run(async () => {
      await Promise.all(
        drafts.map((d) =>
          updateNewRentApex({ id: d.id, newRent: Number(d.newRent) })
        )
      );
      this.toast("New rent saved.");
    });
    await this.load();
  }

  async saveIndex() {
    await this.run(async () => {
      await saveIndexApex({
        series: this.ivSeries,
        year: Number(this.ivYear),
        month: Number(this.ivMonth),
        value: Number(this.ivValue),
        source: this.ivSource
      });
      this.toast("Index value saved.");
      this.ivValue = undefined;
    });
    await this.load();
  }
}
