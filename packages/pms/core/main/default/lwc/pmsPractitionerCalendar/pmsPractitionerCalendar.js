import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSites from "@salesforce/apex/PMS_UIController.getSites";
import getServices from "@salesforce/apex/PMS_UIController.getServices";
import getPractitionerWeek from "@salesforce/apex/PMS_UIController.getPractitionerWeek";
import getFreeSlots from "@salesforce/apex/PMS_UIController.getFreeSlots";
import bookAppointment from "@salesforce/apex/PMS_UIController.bookAppointment";
import {
  addDays,
  mondayOf,
  todayIso,
  weekdayShort,
  errorMessage
} from "c/pmsDateUtils";
import BOOKING_OBJECT from "@salesforce/schema/PMS_Booking__c";

const TIME_FMT = new Intl.DateTimeFormat(undefined, {
  hour: "2-digit",
  minute: "2-digit"
});

function localIso(dt) {
  const d = new Date(dt);
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Practice diary: practitioners × days of the week, with slot finding and booking. */
export default class PmsPractitionerCalendar extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  @api showWeekend = false;

  siteId;
  siteOptions = [];
  serviceOptions = [];
  weekStart = mondayOf(todayIso());
  data;
  loading = false;
  error;

  booking; // { practitionerId, practitionerName, day }
  serviceId;
  slots = [];
  slot;
  accountId;
  contactId;
  mode = "In Person";

  @wire(getSites, { module: "Practice" })
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

  @wire(getServices)
  wiredServices({ data }) {
    if (data) {
      this.serviceOptions = data.map((s) => ({
        label: s.detail ? `${s.label} (${s.detail})` : s.label,
        value: s.value
      }));
    }
  }

  get showSitePicker() {
    return !this.recordId;
  }
  get weekLabel() {
    return `${this.weekStart} – ${addDays(this.weekStart, this.dayCount - 1)}`;
  }
  get dayCount() {
    return this.showWeekend ? 7 : 5;
  }
  get days() {
    const out = [];
    const today = todayIso();
    for (let i = 0; i < this.dayCount; i++) {
      const iso = addDays(this.weekStart, i);
      out.push({
        key: iso,
        iso,
        label: `${weekdayShort(iso)} ${iso.substring(8, 10)}`,
        cls: iso === today ? "pms-today" : ""
      });
    }
    return out;
  }
  get hasPractitioners() {
    return this.data && this.data.practitioners.length > 0;
  }
  get rows() {
    if (!this.data) {
      return [];
    }
    const days = this.days;
    return this.data.practitioners.map((p) => ({
      key: p.value,
      id: p.value,
      name: p.label,
      speciality: p.detail,
      cells: days.map((d) => ({
        key: p.value + d.iso,
        iso: d.iso,
        practitionerId: p.value,
        practitionerName: p.label,
        items: this.data.appointments
          .filter(
            (a) =>
              a.practitionerId === p.value && localIso(a.startTime) === d.iso
          )
          .map((a) => ({
            key: a.id,
            id: a.id,
            time: TIME_FMT.format(new Date(a.startTime)),
            text: `${a.client || ""}${a.service ? " · " + a.service : ""}`,
            cls:
              "pms-appt pms-appt-" +
              (a.status || "").replace(/\s/g, "").toLowerCase()
          }))
      }))
    }));
  }
  get slotOptions() {
    return this.slots.map((s) => ({
      label: TIME_FMT.format(new Date(s)),
      value: s
    }));
  }
  get noSlots() {
    return this.serviceId && this.slots.length === 0;
  }
  get modeOptions() {
    return ["In Person", "Video", "Phone"].map((m) => ({ label: m, value: m }));
  }
  get bookDisabled() {
    return !this.slot || !this.accountId || !this.serviceId || this.loading;
  }

  async load() {
    if (!this.siteId) {
      return;
    }
    this.loading = true;
    this.error = undefined;
    try {
      this.data = await getPractitionerWeek({
        siteId: this.siteId,
        weekStart: this.weekStart
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
  prev() {
    this.weekStart = addDays(this.weekStart, -7);
    this.load();
  }
  next() {
    this.weekStart = addDays(this.weekStart, 7);
    this.load();
  }
  thisWeek() {
    this.weekStart = mondayOf(todayIso());
    this.load();
  }

  open(e) {
    e.stopPropagation();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: e.currentTarget.dataset.id,
        objectApiName: BOOKING_OBJECT.objectApiName,
        actionName: "view"
      }
    });
  }

  startBooking(e) {
    const ds = e.currentTarget.dataset;
    this.booking = {
      practitionerId: ds.practitioner,
      practitionerName: ds.name,
      day: ds.date
    };
    this.slots = [];
    this.slot = undefined;
    if (this.serviceId) {
      this.loadSlots();
    }
  }
  closeBooking() {
    this.booking = undefined;
  }
  handleService(e) {
    this.serviceId = e.detail.value;
    this.loadSlots();
  }
  handleSlot(e) {
    this.slot = e.detail.value;
  }
  handleMode(e) {
    this.mode = e.detail.value;
  }
  handleAccount(e) {
    this.accountId = e.detail.recordId;
  }
  handleContact(e) {
    this.contactId = e.detail.recordId;
  }

  async loadSlots() {
    try {
      this.slots = await getFreeSlots({
        practitionerId: this.booking.practitionerId,
        serviceId: this.serviceId,
        day: this.booking.day
      });
      this.slot = this.slots.length ? this.slots[0] : undefined;
    } catch (e) {
      this.error = errorMessage(e);
    }
  }

  async confirmBooking() {
    this.loading = true;
    try {
      await bookAppointment({
        practitionerId: this.booking.practitionerId,
        serviceId: this.serviceId,
        accountId: this.accountId,
        contactId: this.contactId || null,
        startTime: this.slot,
        mode: this.mode
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Appointment booked",
          variant: "success",
          message: ""
        })
      );
      this.booking = undefined;
      await this.load();
    } catch (err) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Could not book",
          message: errorMessage(err),
          variant: "error"
        })
      );
      this.loading = false;
    }
  }
}
