import { LightningElement } from "lwc";
import basePath from "@salesforce/community/basePath";
import getHome from "@salesforce/apex/PMS_PartnerPortalController.getHome";
import getStatement from "@salesforce/apex/PMS_PartnerPortalController.getStatement";
import acceptWorkOrder from "@salesforce/apex/PMS_PartnerPortalController.acceptWorkOrder";
import submitQuote from "@salesforce/apex/PMS_PartnerPortalController.submitQuote";
import startWork from "@salesforce/apex/PMS_PartnerPortalController.startWork";
import completeWork from "@salesforce/apex/PMS_PartnerPortalController.completeWork";
import submitBill from "@salesforce/apex/PMS_PartnerPortalController.submitBill";
import uploadFile from "@salesforce/apex/PMS_PartnerPortalController.uploadFile";

const MAX_BYTES = 3500000;
const MAX_IMAGE_EDGE = 1800;
const OPEN = [
  "Assigned",
  "Accepted",
  "Quote Requested",
  "Quoted",
  "Approved",
  "In Progress"
];
const STATUS_CLASS = {
  Assigned: "badge badge-new",
  "Quote Requested": "badge badge-new",
  Accepted: "badge badge-active",
  Quoted: "badge badge-wait",
  Approved: "badge badge-active",
  "In Progress": "badge badge-active",
  Completed: "badge badge-done",
  Closed: "badge badge-done",
  Submitted: "badge badge-wait",
  Rejected: "badge badge-bad",
  Withdrawn: "badge badge-muted",
  Paid: "badge badge-done",
  Published: "badge badge-active",
  Let: "badge badge-done",
  "Let from soon": "badge badge-active",
  Vacant: "badge badge-wait"
};

function errorText(e) {
  if (!e) return "Something went wrong.";
  if (e.body && e.body.message) return e.body.message;
  if (e.message) return e.message;
  return String(e);
}

function money(value, currency) {
  if (value === null || value === undefined) return "–";
  try {
    if (currency) {
      return new Intl.NumberFormat("sv-SE", {
        style: "currency",
        currency,
        maximumFractionDigits: 2
      }).format(value);
    }
  } catch {
    // unknown currency code: plain number below
  }
  return new Intl.NumberFormat("sv-SE", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  }).format(value);
}

function day(value) {
  if (!value) return "";
  const d = new Date(String(value).length === 10 ? value + "T12:00:00" : value);
  return d.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric"
  });
}

function month(value) {
  if (!value) return "";
  return new Date(value + "T12:00:00").toLocaleDateString("en-GB", {
    month: "long",
    year: "numeric"
  });
}

function pct(value) {
  return value === null || value === undefined
    ? "–"
    : Number(value).toFixed(1) + " %";
}

function readAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = () => reject(new Error("The file could not be read."));
    r.readAsDataURL(file);
  });
}

/** Phone photos are often 4-8 MB: shrink to a sensible size as JPEG before upload. */
async function prepareFile(file) {
  const drawable = /^image\/(jpeg|png|webp|gif)$/i.test(file.type);
  if (drawable) {
    const url = await readAsDataUrl(file);
    const img = await new Promise((resolve, reject) => {
      const i = new Image();
      i.onload = () => resolve(i);
      i.onerror = () => reject(new Error("The photo could not be opened."));
      i.src = url;
    });
    const scale = Math.min(1, MAX_IMAGE_EDGE / Math.max(img.width, img.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(img.width * scale);
    canvas.height = Math.round(img.height * scale);
    canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
    const data = canvas.toDataURL("image/jpeg", 0.82);
    return {
      name: file.name.replace(/\.[^.]+$/, "") + ".jpg",
      data,
      size: Math.round((data.length * 3) / 4)
    };
  }
  if (file.size > MAX_BYTES) {
    throw new Error(
      "The file is larger than 3.5 MB. Please send a smaller PDF or a photo."
    );
  }
  return { name: file.name, data: await readAsDataUrl(file), size: file.size };
}

export default class PmsPartnerPortal extends LightningElement {
  home;
  loading = true;
  busy = false;
  error;
  notice;
  statement;
  filter = "open";
  openWoId;
  form = {};
  activeForm; // { woId, type: 'quote' | 'bill' | 'complete' | 'photo' }
  pendingFile;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    this.error = undefined;
    try {
      this.home = await getHome();
      if (
        this.home.isVendor &&
        !this.home.isOwner &&
        this.home.workOrders.length === 1
      ) {
        this.openWoId = this.home.workOrders[0].id;
      }
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.loading = false;
    }
  }

  // ------------------------------------------------------------------ view models

  get ready() {
    return !this.loading && this.home;
  }

  get nothingYet() {
    return this.ready && !this.home.isOwner && !this.home.isVendor;
  }

  get greeting() {
    return this.home && this.home.userName
      ? "Welcome, " + this.home.userName
      : "Welcome";
  }

  get sites() {
    return (this.home ? this.home.sites : []).map((s) => {
      const f = s.monthToDate || {};
      return {
        ...s,
        periodLabel:
          "This month so far (" +
          day(f.periodStart) +
          " – " +
          day(f.periodEnd) +
          ")",
        gross: money(f.gross, s.currencyCode),
        expenses: money(f.expenses, s.currencyCode),
        fee: money(f.fee, s.currencyCode),
        feeLabel: "Management fee (" + (f.feePercent || 0) + " %)",
        net: money(f.net, s.currencyCode),
        arrears: money(f.arrears, s.currencyCode),
        hasArrears: f.arrears > 0,
        occupancy: pct(f.occupancyPct),
        occupancyBasis: f.occupancyBasis || "",
        hasUnits: s.units && s.units.length > 0,
        units: (s.units || []).map((u, i) => ({
          ...u,
          key: s.id + "-" + i,
          badge: STATUS_CLASS[u.status] || "badge",
          leaseEndLabel: u.leaseEnd ? day(u.leaseEnd) : "",
          rentLabel: u.rent ? money(u.rent, s.currencyCode) : ""
        }))
      };
    });
  }

  get statements() {
    return (this.home ? this.home.statements : []).map((s) => ({
      ...s,
      period: month(s.periodStart),
      grossLabel: money(s.gross, s.currencyCode),
      expensesLabel: money(s.expenses, s.currencyCode),
      feeLabel: money(s.fee, s.currencyCode),
      netLabel: money(s.net, s.currencyCode),
      occupancyLabel: pct(s.occupancyPct),
      badge: STATUS_CLASS[s.status] || "badge"
    }));
  }

  get hasStatements() {
    return this.statements.length > 0;
  }

  get statementView() {
    if (!this.statement) return null;
    const s = this.statement.statement;
    const c = s.currencyCode;
    const line = (l, i) => ({
      ...l,
      key: i,
      dateLabel: day(l.lineDate),
      amountLabel: money(l.amount, c)
    });
    return {
      title: s.siteName + " – " + month(s.periodStart),
      name: s.name,
      status: s.status,
      badge: STATUS_CLASS[s.status] || "badge",
      gross: money(s.gross, c),
      expenses: money(s.expenses, c),
      fee: money(s.fee, c),
      feeLabel: "Management fee (" + (this.statement.feePercent || 0) + " %)",
      net: money(s.net, c),
      arrears: money(s.arrears, c),
      occupancy: pct(s.occupancyPct),
      occupancyBasis: s.occupancyBasis || "",
      income: (this.statement.income || []).map(line),
      costs: (this.statement.costs || []).map(line),
      hasIncome: (this.statement.income || []).length > 0,
      hasCosts: (this.statement.costs || []).length > 0
    };
  }

  get filterOptions() {
    const all = this.home ? this.home.workOrders : [];
    const open = all.filter((w) => OPEN.includes(w.status)).length;
    return [
      { value: "open", label: "Open (" + open + ")" },
      { value: "done", label: "Done (" + (all.length - open) + ")" },
      { value: "all", label: "All (" + all.length + ")" }
    ].map((o) => ({
      ...o,
      variant: o.value === this.filter ? "brand" : "neutral"
    }));
  }

  get workOrders() {
    const all = this.home ? this.home.workOrders : [];
    return all
      .filter(
        (w) =>
          this.filter === "all" ||
          (this.filter === "open") === OPEN.includes(w.status)
      )
      .map((w) => {
        const c = w.currencyCode;
        const af =
          this.activeForm && this.activeForm.woId === w.id
            ? this.activeForm.type
            : null;
        return {
          ...w,
          expanded: this.openWoId === w.id,
          toggleLabel: this.openWoId === w.id ? "Hide" : "Open",
          badge: STATUS_CLASS[w.status] || "badge",
          urgent: w.priority === "Urgent" || w.priority === "High",
          scheduledLabel: w.scheduledDate ? day(w.scheduledDate) : "",
          nteLabel: w.notToExceed ? money(w.notToExceed, c) : "",
          createdLabel: day(w.created),
          showQuoteForm: af === "quote",
          showBillForm: af === "bill",
          showCompleteForm: af === "complete",
          showPhotoForm: af === "photo",
          noForm: !af,
          hasQuotes: w.quotes.length > 0,
          hasBills: w.bills.length > 0,
          hasFiles: w.files.length > 0,
          quotes: w.quotes.map((q) => ({
            ...q,
            badge: STATUS_CLASS[q.status] || "badge",
            totalLabel: money(q.total, c),
            validLabel: q.validUntil ? "valid until " + day(q.validUntil) : ""
          })),
          bills: w.bills.map((b) => ({
            ...b,
            badge: STATUS_CLASS[b.status] || "badge",
            totalLabel: money(b.total, c),
            dateLabel: day(b.billDate),
            paidLabel: b.paidDate ? "paid " + day(b.paidDate) : ""
          })),
          files: w.files.map((f) => ({
            ...f,
            url:
              (basePath || "") +
              "/sfc/servlet.shepherd/version/download/" +
              f.versionId,
            label:
              f.kind + ": " + f.title + (f.extension ? "." + f.extension : "")
          }))
        };
      });
  }

  get hasWorkOrders() {
    return this.workOrders.length > 0;
  }

  get fileLabel() {
    return this.pendingFile
      ? this.pendingFile.name +
          " (" +
          Math.round(this.pendingFile.size / 1024) +
          " KB)"
      : "No file chosen";
  }

  // ------------------------------------------------------------------ owner handlers

  async openStatement(event) {
    this.busy = true;
    this.error = undefined;
    try {
      this.statement = await getStatement({
        statementId: event.currentTarget.dataset.id
      });
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.busy = false;
    }
  }

  closeStatement() {
    this.statement = undefined;
  }

  printStatement() {
    window.print();
  }

  // ------------------------------------------------------------------ vendor handlers

  setFilter(event) {
    this.filter = event.currentTarget.dataset.value;
  }

  toggleWorkOrder(event) {
    const id = event.currentTarget.dataset.id;
    this.openWoId = this.openWoId === id ? undefined : id;
    this.cancelForm();
  }

  showForm(event) {
    const { id, type } = event.currentTarget.dataset;
    this.activeForm = { woId: id, type };
    this.form =
      type === "bill"
        ? { billDate: new Date().toISOString().slice(0, 10) }
        : {};
    this.pendingFile = undefined;
    this.notice = undefined;
    this.error = undefined;
  }

  cancelForm() {
    this.activeForm = undefined;
    this.form = {};
    this.pendingFile = undefined;
  }

  handleField(event) {
    this.form = {
      ...this.form,
      [event.target.dataset.field]: event.target.value
    };
  }

  async handleFile(event) {
    const file = event.target.files && event.target.files[0];
    this.pendingFile = undefined;
    if (!file) return;
    try {
      this.busy = true;
      const prepared = await prepareFile(file);
      if (prepared.size > MAX_BYTES) {
        throw new Error(
          "The file is larger than 3.5 MB. Please send a smaller file."
        );
      }
      this.pendingFile = prepared;
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.busy = false;
    }
  }

  async accept(event) {
    await this.run(
      () => acceptWorkOrder({ workOrderId: event.currentTarget.dataset.id }),
      "Job accepted. Thank you!"
    );
  }

  async start(event) {
    await this.run(
      () => startWork({ workOrderId: event.currentTarget.dataset.id }),
      "Marked as in progress."
    );
  }

  async sendQuote() {
    const f = this.form;
    await this.run(
      () =>
        submitQuote({
          workOrderId: this.activeForm.woId,
          formJson: JSON.stringify({
            amount: f.amount ? Number(f.amount) : null,
            tax: f.tax ? Number(f.tax) : 0,
            description: f.description,
            validUntil: f.validUntil
          }),
          fileName: this.pendingFile ? this.pendingFile.name : null,
          base64Data: this.pendingFile ? this.pendingFile.data : null
        }),
      "Quote sent. We will let you know when it is approved."
    );
  }

  async sendComplete() {
    await this.run(
      () =>
        completeWork({
          workOrderId: this.activeForm.woId,
          notes: this.form.notes
        }),
      "Marked as completed. You can now send your invoice."
    );
  }

  async sendBill() {
    const f = this.form;
    await this.run(
      () =>
        submitBill({
          workOrderId: this.activeForm.woId,
          formJson: JSON.stringify({
            amount: f.amount ? Number(f.amount) : null,
            tax: f.tax ? Number(f.tax) : 0,
            invoiceNumber: f.invoiceNumber,
            billDate: f.billDate,
            dueDate: f.dueDate,
            description: f.notes
          }),
          fileName: this.pendingFile ? this.pendingFile.name : null,
          base64Data: this.pendingFile ? this.pendingFile.data : null
        }),
      "Invoice sent."
    );
  }

  async sendPhoto() {
    if (!this.pendingFile) {
      this.error = "Choose a photo or PDF first.";
      return;
    }
    await this.run(
      () =>
        uploadFile({
          workOrderId: this.activeForm.woId,
          kind: this.pendingFile.name.toLowerCase().endsWith(".pdf")
            ? "Document"
            : "Photo",
          fileName: this.pendingFile.name,
          base64Data: this.pendingFile.data
        }),
      "File added."
    );
  }

  /** Runs a vendor action, swaps in the refreshed work order and closes the form. */
  async run(action, message) {
    this.busy = true;
    this.error = undefined;
    this.notice = undefined;
    try {
      const updated = await action();
      if (updated) {
        const list = this.home.workOrders.map((w) => {
          return w.id === updated.id ? updated : w;
        });
        this.home = { ...this.home, workOrders: list };
        this.openWoId = updated.id;
      }
      this.cancelForm();
      this.notice = message;
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.busy = false;
    }
  }

  dismissNotice() {
    this.notice = undefined;
  }
}
