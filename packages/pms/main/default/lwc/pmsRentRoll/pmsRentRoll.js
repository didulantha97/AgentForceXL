import { LightningElement, api, wire } from "lwc";
import getSites from "@salesforce/apex/PMS_UIController.getSites";
import getRentRoll from "@salesforce/apex/PMS_UIController.getRentRoll";
import { errorMessage } from "c/pmsDateUtils";

const COLUMNS = [
  {
    label: "Unit",
    fieldName: "unitUrl",
    type: "url",
    typeAttributes: { label: { fieldName: "unit" } },
    sortable: true
  },
  { label: "Type", fieldName: "unitType", sortable: true },
  {
    label: "m²",
    fieldName: "sizeSqm",
    type: "number",
    initialWidth: 80,
    sortable: true
  },
  { label: "Status", fieldName: "status", initialWidth: 100, sortable: true },
  { label: "Tenant", fieldName: "tenant", sortable: true },
  {
    label: "Lease",
    fieldName: "leaseUrl",
    type: "url",
    typeAttributes: { label: { fieldName: "leaseNumber" } }
  },
  { label: "Rent", fieldName: "rent", type: "currency", sortable: true },
  { label: "Frequency", fieldName: "frequency", initialWidth: 110 },
  {
    label: "Lease end",
    fieldName: "leaseEnd",
    type: "date-local",
    sortable: true
  },
  {
    label: "Arrears",
    fieldName: "arrears",
    type: "currency",
    sortable: true,
    cellAttributes: { class: { fieldName: "arrearsClass" } }
  },
  {
    label: "Days overdue",
    fieldName: "maxDaysOverdue",
    type: "number",
    initialWidth: 120,
    sortable: true
  }
];

/** Property rent roll: every unit with its tenant, rent, lease end and arrears. */
export default class PmsRentRoll extends LightningElement {
  @api recordId;

  columns = COLUMNS;
  siteId;
  siteOptions = [];
  roll;
  filter = "all";
  sortedBy = "unitUrl";
  sortDirection = "asc";
  loading = false;
  error;

  @wire(getSites, { module: "Property" })
  wiredSites({ data, error }) {
    if (data) {
      this.siteOptions = data.map((s) => ({ label: s.label, value: s.value }));
      if (!this.siteId) {
        this.siteId =
          this.recordId ||
          (this.siteOptions.length ? this.siteOptions[0].value : null);
        this.load();
      }
    } else if (error) {
      this.error = errorMessage(error);
    }
  }

  get showSitePicker() {
    return !this.recordId;
  }
  get filterOptions() {
    return [
      { label: "All units", value: "all" },
      { label: "Let", value: "let" },
      { label: "Vacant", value: "vacant" },
      { label: "In arrears", value: "arrears" },
      { label: "Ending in 90 days", value: "expiring" }
    ];
  }

  get kpis() {
    const r = this.roll || {
      units: 0,
      occupied: 0,
      occupancyPct: 0,
      monthlyRent: 0,
      totalArrears: 0
    };
    return [
      { key: "u", label: "Units", value: r.units, isCurrency: false },
      {
        key: "o",
        label: "Occupancy",
        value: r.occupancyPct + "%",
        isCurrency: false
      },
      {
        key: "v",
        label: "Vacant",
        value: r.units - r.occupied,
        isCurrency: false
      },
      {
        key: "m",
        label: "Monthly rent",
        value: r.monthlyRent,
        isCurrency: true
      },
      { key: "a", label: "Arrears", value: r.totalArrears, isCurrency: true }
    ];
  }

  get rows() {
    if (!this.roll) {
      return [];
    }
    const in90 = new Date();
    in90.setDate(in90.getDate() + 90);
    const limit = in90.toISOString().substring(0, 10);
    const rows = this.roll.rows
      .map((r) => ({
        ...r,
        unitUrl: "/" + r.unitId,
        leaseUrl: r.leaseId ? "/" + r.leaseId : null,
        arrearsClass: r.arrears > 0 ? "slds-text-color_error" : ""
      }))
      .filter((r) => {
        switch (this.filter) {
          case "let":
            return !!r.leaseId;
          case "vacant":
            return !r.leaseId;
          case "arrears":
            return r.arrears > 0;
          case "expiring":
            return r.leaseEnd && r.leaseEnd <= limit;
          default:
            return true;
        }
      });
    const field = this.sortedBy === "unitUrl" ? "unit" : this.sortedBy;
    const dir = this.sortDirection === "asc" ? 1 : -1;
    return rows.sort((a, b) => {
      const x = a[field] === undefined || a[field] === null ? "" : a[field];
      const y = b[field] === undefined || b[field] === null ? "" : b[field];
      return x > y ? dir : x < y ? -dir : 0;
    });
  }

  async load() {
    if (!this.siteId) {
      return;
    }
    this.loading = true;
    this.error = undefined;
    try {
      this.roll = await getRentRoll({ siteId: this.siteId });
    } catch (e) {
      this.error = errorMessage(e);
    } finally {
      this.loading = false;
    }
  }

  handleSite(e) {
    this.siteId = e.detail.value;
    this.load();
  }
  handleFilter(e) {
    this.filter = e.detail.value;
  }
  handleSort(e) {
    this.sortedBy = e.detail.fieldName;
    this.sortDirection = e.detail.sortDirection;
  }

  exportCsv() {
    const header = [
      "Unit",
      "Type",
      "Size m2",
      "Status",
      "Tenant",
      "Lease",
      "Rent",
      "Frequency",
      "Lease end",
      "Arrears",
      "Days overdue"
    ];
    const esc = (v) =>
      '"' +
      String(v === undefined || v === null ? "" : v).replace(/"/g, '""') +
      '"';
    const lines = [header.map(esc).join(",")].concat(
      this.rows.map((r) =>
        [
          r.unit,
          r.unitType,
          r.sizeSqm,
          r.status,
          r.tenant,
          r.leaseNumber,
          r.rent,
          r.frequency,
          r.leaseEnd,
          r.arrears,
          r.maxDaysOverdue
        ]
          .map(esc)
          .join(",")
      )
    );
    const link = document.createElement("a");
    link.href =
      "data:text/csv;charset=utf-8," + encodeURIComponent(lines.join("\n"));
    link.download = "rent-roll.csv";
    link.click();
  }
}
