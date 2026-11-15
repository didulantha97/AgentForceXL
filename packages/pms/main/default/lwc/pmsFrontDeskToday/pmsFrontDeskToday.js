import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSites from "@salesforce/apex/PMS_UIController.getSites";
import getFrontDesk from "@salesforce/apex/PMS_UIController.getFrontDesk";
import checkIn from "@salesforce/apex/PMS_UIController.checkIn";
import checkOut from "@salesforce/apex/PMS_UIController.checkOut";
import { todayIso, errorMessage } from "c/pmsDateUtils";

/** Front desk "today" board: arrivals with room assignment, in-house guests and departures. */
export default class PmsFrontDeskToday extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  siteId;
  siteOptions = [];
  businessDate = todayIso();
  data;
  roomChoice = {};
  loading = false;
  error;

  @wire(getSites, { module: "Hotel" })
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

  get kpis() {
    const d = this.data || {
      arrivals: [],
      departures: [],
      inHouse: [],
      freeRooms: [],
      totalRooms: 0,
      dirtyRooms: 0
    };
    const occupied = d.inHouse.length + d.departures.length;
    const occ = d.totalRooms ? Math.round((occupied * 100) / d.totalRooms) : 0;
    return [
      { key: "arr", label: "Arrivals", value: d.arrivals.length },
      { key: "dep", label: "Departures", value: d.departures.length },
      { key: "inh", label: "In house", value: d.inHouse.length },
      { key: "occ", label: "Occupancy", value: occ + "%" },
      { key: "free", label: "Free rooms", value: d.freeRooms.length },
      { key: "dirty", label: "Dirty rooms", value: d.dirtyRooms }
    ];
  }

  get arrivals() {
    if (!this.data) {
      return [];
    }
    return this.data.arrivals.map((a) => {
      const sameType = this.data.freeRooms.filter(
        (r) => !a.roomType || r.roomType === a.roomType
      );
      const pool = sameType.length ? sameType : this.data.freeRooms;
      const options = pool.map((r) => ({
        label: `${r.name}${r.status === "Dirty" ? " (dirty)" : ""}`,
        value: r.id
      }));
      if (a.roomId && !options.find((o) => o.value === a.roomId)) {
        options.unshift({ label: a.room + " (assigned)", value: a.roomId });
      }
      return {
        ...a,
        key: a.id,
        options,
        selectedRoom:
          this.roomChoice[a.id] ||
          a.roomId ||
          (options.length ? options[0].value : null)
      };
    });
  }
  get inHouse() {
    return this.data ? this.data.inHouse.map((r) => ({ ...r, key: r.id })) : [];
  }
  get departures() {
    return this.data
      ? this.data.departures.map((r) => ({
          ...r,
          key: r.id,
          owes: r.balance && r.balance > 0
        }))
      : [];
  }
  get arrivalsLabel() {
    return `Arrivals (${this.arrivals.length})`;
  }
  get inHouseLabel() {
    return `In house (${this.inHouse.length})`;
  }
  get departuresLabel() {
    return `Departures (${this.departures.length})`;
  }
  get noArrivals() {
    return this.arrivals.length === 0;
  }
  get noInHouse() {
    return this.inHouse.length === 0;
  }
  get noDepartures() {
    return this.departures.length === 0;
  }

  async load() {
    if (!this.siteId) {
      return;
    }
    this.loading = true;
    this.error = undefined;
    try {
      this.data = await getFrontDesk({
        siteId: this.siteId,
        businessDate: this.businessDate
      });
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
  handleDate(e) {
    this.businessDate = e.detail.value;
    this.load();
  }
  handleRoom(e) {
    this.roomChoice = {
      ...this.roomChoice,
      [e.target.dataset.id]: e.detail.value
    };
  }

  async doCheckIn(e) {
    const id = e.currentTarget.dataset.id;
    const row = this.arrivals.find((a) => a.id === id);
    await this.run(
      () => checkIn({ bookingId: id, roomId: row ? row.selectedRoom : null }),
      `${row ? row.guest : "Guest"} checked in`
    );
  }

  async doCheckOut(e) {
    const id = e.currentTarget.dataset.id;
    const row =
      this.departures.find((a) => a.id === id) ||
      this.inHouse.find((a) => a.id === id);
    await this.run(
      () => checkOut({ bookingId: id }),
      `${row ? row.guest : "Guest"} checked out · folio issued`
    );
  }

  async run(action, successMessage) {
    this.loading = true;
    try {
      await action();
      this.dispatchEvent(
        new ShowToastEvent({
          title: successMessage,
          variant: "success",
          message: ""
        })
      );
      await this.load();
    } catch (err) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Action failed",
          message: errorMessage(err),
          variant: "error"
        })
      );
      this.loading = false;
    }
  }

  open(e) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: e.currentTarget.dataset.id,
        objectApiName: "PMS_Booking__c",
        actionName: "view"
      }
    });
  }
}
