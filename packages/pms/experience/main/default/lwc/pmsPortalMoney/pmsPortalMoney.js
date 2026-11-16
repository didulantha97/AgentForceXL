import { LightningElement, api } from "lwc";
import getMyPayments from "@salesforce/apex/PMS_PortalMoneyController.getMyPayments";

function money(amount, currencyCode) {
  if (amount === null || amount === undefined) {
    return "";
  }
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currencyCode || "SEK"
    }).format(amount);
  } catch {
    return `${amount} ${currencyCode || ""}`.trim();
  }
}

function day(value) {
  if (!value) {
    return "";
  }
  const d =
    typeof value === "string" && value.length === 10
      ? new Date(`${value}T12:00:00`)
      : new Date(value);
  return new Intl.DateTimeFormat(undefined, {
    day: "numeric",
    month: "short",
    year: "numeric"
  }).format(d);
}

const STAGE_TEXT = {
  "Reminder 1": "Reminder sent",
  "Reminder 2": "Second reminder sent",
  "Plan Offered": "Payment plan offered",
  "Payment Plan": "On a payment plan",
  Collections: "Passed to collections"
};

export default class PmsPortalMoney extends LightningElement {
  @api heading = "My payments";
  data;
  error;
  loading = true;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.data = await getMyPayments();
      this.error = undefined;
    } catch (e) {
      this.error =
        e && e.body
          ? e.body.message
          : "We could not load your payments just now. Please try again later.";
    } finally {
      this.loading = false;
    }
  }

  get invoices() {
    return (this.data ? this.data.invoices : []).map((i) => ({
      ...i,
      balanceText: money(i.balance, i.currencyCode),
      dueText: day(i.dueDate),
      stageText: STAGE_TEXT[i.stage] || "",
      rowClass: i.overdue ? "row overdue" : "row"
    }));
  }

  get instalments() {
    return (this.data ? this.data.instalments : []).map((i, idx) => ({
      ...i,
      key: `${i.invoiceName}-${i.instalmentNumber}-${idx}`,
      amountText: money(i.amount, i.currencyCode),
      dueText: day(i.dueDate),
      rowClass: i.overdue ? "row overdue" : "row"
    }));
  }

  get cards() {
    return (this.data ? this.data.cardsNeeded : []).map((c) => ({
      ...c,
      startText: day(c.startsAt)
    }));
  }

  get rent() {
    return (this.data ? this.data.rentChanges : []).map((r, idx) => ({
      ...r,
      key: `${r.leaseName}-${idx}`,
      oldText: money(r.oldRent, r.currencyCode),
      newText: money(r.newRent, r.currencyCode),
      fromText: day(r.effectiveDate),
      changeText:
        r.changePercent === null || r.changePercent === undefined
          ? ""
          : `${Number(r.changePercent).toFixed(2)} %`
    }));
  }

  get hasInvoices() {
    return this.invoices.length > 0;
  }
  get hasInstalments() {
    return this.instalments.length > 0;
  }
  get hasCards() {
    return this.cards.length > 0;
  }
  get hasRent() {
    return this.rent.length > 0;
  }
  get nothing() {
    return (
      this.data &&
      this.data.hasAccount &&
      !this.hasInvoices &&
      !this.hasInstalments &&
      !this.hasCards &&
      !this.hasRent
    );
  }
  get noAccount() {
    return this.data && !this.data.hasAccount;
  }

  pay(event) {
    const url = event.currentTarget.dataset.url;
    if (url) {
      window.open(url, "_blank", "noopener");
    }
  }
}
