import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getEnabledModules from "@salesforce/apex/PMS_UIController.getEnabledModules";
import getSites from "@salesforce/apex/PMS_UIController.getSites";
import getSpaceTypes from "@salesforce/apex/PMS_UIController.getSpaceTypes";
import getRatePlans from "@salesforce/apex/PMS_UIController.getRatePlans";
import searchAvailability from "@salesforce/apex/PMS_UIController.searchAvailability";
import createBooking from "@salesforce/apex/PMS_UIController.createBooking";
import { addDays, todayIso, errorMessage } from "c/pmsDateUtils";

const LABELS = {
  Property: {
    booking: "Lease",
    space: "Unit",
    start: "Lease start",
    end: "Lease end"
  },
  Hotel: {
    booking: "Reservation",
    space: "Room",
    start: "Arrival",
    end: "Departure"
  },
  Project: {
    booking: "Allocation",
    space: "Resource",
    start: "From",
    end: "To"
  }
};

export default class PmsBookingWizard extends NavigationMixin(
  LightningElement
) {
  /** Site record id when placed on a Site record page. */
  @api recordId;
  /** Optional fixed module (Property, Hotel or Project). */
  @api defaultModule;

  step = 1;
  module;
  siteId;
  spaceTypeId;
  ratePlanId;
  startDate = todayIso();
  endDate = addDays(todayIso(), 1);
  adults = 1;
  children = 0;

  moduleOptions = [];
  siteOptions = [];
  spaceTypeOptions = [];
  ratePlanOptions = [];
  results = [];
  selected;

  accountId;
  contactId;
  channel = "Direct";
  specialRequests;

  loading = false;
  error;

  @wire(getEnabledModules)
  wiredModules({ data, error }) {
    if (data) {
      this.moduleOptions = data
        .filter((m) => m !== "Practice")
        .map((m) => ({ label: m, value: m }));
      if (!this.module) {
        const preferred =
          this.defaultModule && data.includes(this.defaultModule)
            ? this.defaultModule
            : null;
        this.module =
          preferred ||
          (this.moduleOptions.length ? this.moduleOptions[0].value : null);
        this.loadSites();
      }
    } else if (error) {
      this.error = errorMessage(error);
    }
  }

  get labels() {
    return LABELS[this.module] || LABELS.Hotel;
  }

  get isStep1() {
    return this.step === 1;
  }
  get isStep2() {
    return this.step === 2;
  }
  get isStep3() {
    return this.step === 3;
  }
  get isHotel() {
    return this.module === "Hotel";
  }
  get siteLocked() {
    return !!this.recordId;
  }
  get hasResults() {
    return this.results.length > 0;
  }
  get noResults() {
    return this.step === 2 && !this.loading && this.results.length === 0;
  }
  get searchDisabled() {
    return (
      !this.module ||
      !this.siteId ||
      !this.startDate ||
      !this.endDate ||
      this.loading
    );
  }
  get confirmDisabled() {
    return !this.accountId || this.loading;
  }
  get channelOptions() {
    return [
      "Direct",
      "Phone",
      "Walk-in",
      "Website",
      "Corporate",
      "Travel Agent",
      "OTA"
    ].map((c) => ({ label: c, value: c }));
  }
  get title() {
    return "New " + this.labels.booking;
  }

  async loadSites() {
    this.error = undefined;
    try {
      this.siteOptions = (await getSites({ module: this.module })).map((s) => ({
        label: s.detail ? `${s.label} (${s.detail})` : s.label,
        value: s.value
      }));
      if (this.recordId) {
        this.siteId = this.recordId;
      } else if (!this.siteOptions.find((o) => o.value === this.siteId)) {
        this.siteId = this.siteOptions.length
          ? this.siteOptions[0].value
          : null;
      }
      await this.loadSiteDetails();
    } catch (e) {
      this.error = errorMessage(e);
    }
  }

  async loadSiteDetails() {
    if (!this.siteId) {
      this.spaceTypeOptions = [];
      this.ratePlanOptions = [];
      return;
    }
    const [types, plans] = await Promise.all([
      getSpaceTypes({ siteId: this.siteId }),
      getRatePlans({ siteId: this.siteId, module: this.module })
    ]);
    this.spaceTypeOptions = [
      { label: "Any", value: "" },
      ...types.map((t) => ({ label: t.label, value: t.value }))
    ];
    this.ratePlanOptions = [
      { label: "Standard price", value: "" },
      ...plans.map((p) => ({ label: p.label, value: p.value }))
    ];
    this.spaceTypeId = "";
    this.ratePlanId = plans.length ? plans[0].value : "";
  }

  handleModule(e) {
    this.module = e.detail.value;
    this.results = [];
    this.loadSites();
  }
  handleSite(e) {
    this.siteId = e.detail.value;
    this.loadSiteDetails().catch((err) => (this.error = errorMessage(err)));
  }
  handleField(e) {
    const name = e.target.name;
    this[name] = e.detail.value;
    if (name === "startDate" && this.endDate <= this.startDate) {
      this.endDate = addDays(
        this.startDate,
        this.module === "Property" ? 365 : 1
      );
    }
  }
  handleAccount(e) {
    this.accountId = e.detail.recordId;
  }
  handleContact(e) {
    this.contactId = e.detail.recordId;
  }

  async search() {
    if (this.endDate <= this.startDate) {
      this.error = "The end must be after the start.";
      return;
    }
    this.loading = true;
    this.error = undefined;
    try {
      const rows = await searchAvailability({
        module: this.module,
        siteId: this.siteId,
        spaceTypeId: this.spaceTypeId || null,
        ratePlanId: this.ratePlanId || null,
        startDate: this.startDate,
        endDate: this.endDate,
        guests: Number(this.adults || 0) + Number(this.children || 0)
      });
      this.results = rows.map((r) => ({
        ...r,
        key: r.spaceId,
        summary: `${r.quote.units} × ${r.quote.unitPrice} (${r.quote.pricingBasis.toLowerCase()})`
      }));
      this.step = 2;
    } catch (e) {
      this.error = errorMessage(e);
    } finally {
      this.loading = false;
    }
  }

  select(e) {
    const id = e.currentTarget.dataset.id;
    this.selected = this.results.find((r) => r.spaceId === id);
    this.step = 3;
  }

  back() {
    this.step = Math.max(1, this.step - 1);
  }

  async confirm() {
    this.loading = true;
    this.error = undefined;
    try {
      const request = {
        module: this.module,
        siteId: this.siteId,
        spaceId: this.selected.spaceId,
        spaceTypeId: this.selected.spaceTypeId,
        ratePlanId: this.ratePlanId || null,
        accountId: this.accountId,
        contactId: this.contactId || null,
        startDate: this.startDate,
        endDate: this.endDate,
        adults: Number(this.adults || 0),
        children: Number(this.children || 0),
        channel: this.channel,
        specialRequests: this.specialRequests,
        status: "Confirmed"
      };
      const bookingId = await createBooking({
        requestJson: JSON.stringify(request)
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: `${this.labels.booking} created`,
          variant: "success",
          message: ""
        })
      );
      this.reset();
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: bookingId,
          objectApiName: "PMS_Booking__c",
          actionName: "view"
        }
      });
    } catch (e) {
      this.error = errorMessage(e);
    } finally {
      this.loading = false;
    }
  }

  reset() {
    this.step = 1;
    this.results = [];
    this.selected = undefined;
    this.accountId = undefined;
    this.contactId = undefined;
    this.specialRequests = undefined;
  }
}
