import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getCalendar from "@salesforce/apex/PMS_PricingCalendarController.getCalendar";
import recalculate from "@salesforce/apex/PMS_PricingCalendarController.recalculate";
import setPrice from "@salesforce/apex/PMS_PricingCalendarController.setPrice";
import unlock from "@salesforce/apex/PMS_PricingCalendarController.unlock";

export default class PmsPricingCalendar extends LightningElement {
  @api recordId;
  cal;
  rows = [];
  busy = false;
  error;
  days = "30";
  editing;
  editAmount;
  dayOptions = [
    { label: "14 days", value: "14" },
    { label: "30 days", value: "30" },
    { label: "60 days", value: "60" },
    { label: "120 days", value: "120" }
  ];

  connectedCallback() {
    this.load();
  }

  money(v) {
    if (v === null || v === undefined) return "";
    try {
      return new Intl.NumberFormat(undefined, {
        maximumFractionDigits: 0
      }).format(v);
    } catch {
      return String(v);
    }
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
      this.cal = await getCalendar({
        recordId: this.recordId,
        days: Number(this.days)
      });
      this.build();
    });
  }

  build() {
    const cal = this.cal;
    this.rows = (cal.nights || []).map((n) => {
      const weekend = n.dayName === "Fri" || n.dayName === "Sat";
      return {
        key: n.night,
        label: n.night.substring(5),
        dayName: n.dayName,
        rowClass: weekend ? "slds-theme_shade" : "",
        cells: n.cells.map((c) => {
          const above = c.amount != null && c.base != null && c.amount > c.base;
          const below = c.amount != null && c.base != null && c.amount < c.base;
          return {
            ...c,
            key: n.night + "|" + c.roomTypeId,
            amountText: c.amount == null ? "-" : this.money(c.amount),
            sub: c.occupancy == null ? "" : Math.round(c.occupancy) + "% sold",
            title: c.notes || "",
            cls:
              "slds-cell-wrap" +
              (above
                ? " slds-text-color_success"
                : below
                  ? " slds-text-color_error"
                  : "") +
              (c.rateId ? " slds-is-hovered" : "")
          };
        })
      };
    });
  }

  onDays(e) {
    this.days = e.detail.value;
    this.load();
  }

  async recalc() {
    await this.run(async () => {
      const r = await recalculate({ recordId: this.recordId });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Rates recalculated",
          message: r.summary,
          variant: "success"
        })
      );
    });
    await this.load();
  }

  openEdit(e) {
    const key = e.currentTarget.dataset.key;
    for (const r of this.rows) {
      const c = r.cells.find((x) => x.key === key);
      if (c) {
        if (!c.rateId) {
          this.error =
            "No daily rate for this night yet. Click Recalculate now first.";
          return;
        }
        const type = this.cal.roomTypes.find((t) => t.id === c.roomTypeId);
        this.editing = {
          rateId: c.rateId,
          locked: c.locked,
          label: `${type ? type.name : ""}, ${r.dayName} ${r.label}`,
          base: this.money(c.base),
          occ: c.occupancy == null ? "-" : Math.round(c.occupancy) + "%",
          notes: c.notes || ""
        };
        this.editAmount = c.amount;
        return;
      }
    }
  }

  onEditAmount(e) {
    this.editAmount = e.detail.value;
  }

  closeEdit() {
    this.editing = undefined;
  }

  async savePrice() {
    const id = this.editing.rateId;
    await this.run(async () => {
      await setPrice({ rateId: id, amount: Number(this.editAmount) });
      this.editing = undefined;
    });
    await this.load();
  }

  async unlockPrice() {
    const id = this.editing.rateId;
    await this.run(async () => {
      await unlock({ rateId: id });
      this.editing = undefined;
    });
    await this.load();
  }
}
