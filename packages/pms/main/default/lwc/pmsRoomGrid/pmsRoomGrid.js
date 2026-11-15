import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSites from "@salesforce/apex/PMS_UIController.getSites";
import getRoomGrid from "@salesforce/apex/PMS_UIController.getRoomGrid";
import moveBooking from "@salesforce/apex/PMS_UIController.moveBooking";
import {
  addDays,
  daysBetween,
  todayIso,
  weekdayShort,
  isWeekend,
  errorMessage
} from "c/pmsDateUtils";

/**
 * Hotel tape chart: rooms down the side, dates across the top.
 * Drag a booking onto another room and/or day to move it (length is kept).
 */
export default class PmsRoomGrid extends NavigationMixin(LightningElement) {
  @api recordId;
  @api days = 14;

  siteId;
  siteOptions = [];
  startDate = addDays(todayIso(), -1);
  data;
  loading = false;
  error;
  dragBookingId;

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
  get span() {
    return Number(this.days) || 14;
  }
  get title() {
    return this.data ? `Room grid · ${this.data.siteName}` : "Room grid";
  }
  get hasRooms() {
    return this.data && this.data.rooms.length > 0;
  }

  get dateHeaders() {
    const out = [];
    const today = todayIso();
    for (let i = 0; i < this.span; i++) {
      const iso = addDays(this.startDate, i);
      let cls = "pms-day";
      if (isWeekend(iso)) {
        cls += " pms-weekend";
      }
      if (iso === today) {
        cls += " pms-today";
      }
      out.push({
        key: iso,
        iso,
        weekday: weekdayShort(iso),
        day: iso.substring(8, 10),
        cls
      });
    }
    return out;
  }

  get rows() {
    if (!this.data) {
      return [];
    }
    const gridEnd = addDays(this.startDate, this.span);
    const byRoom = {};
    this.data.bookings.forEach((b) => {
      (byRoom[b.spaceId] = byRoom[b.spaceId] || []).push(b);
    });
    return this.data.rooms.map((room) => {
      const bookings = (byRoom[room.id] || [])
        .slice()
        .sort((a, b) => (a.startDate < b.startDate ? -1 : 1));
      const cells = [];
      let i = 0;
      while (i < this.span) {
        const iso = addDays(this.startDate, i);
        const b = bookings.find((x) => x.startDate <= iso && x.endDate > iso);
        if (b) {
          const visibleEnd = b.endDate < gridEnd ? b.endDate : gridEnd;
          const len = Math.max(1, daysBetween(iso, visibleEnd));
          cells.push({
            key: room.id + iso,
            isBooking: true,
            colspan: len,
            bookingId: b.id,
            label: b.guest || b.name,
            title: `${b.name} · ${b.guest || ""} · ${b.startDate} → ${b.endDate} · ${b.status}`,
            cls:
              "pms-booking pms-status-" +
              (b.status || "").replace(/\s/g, "").toLowerCase(),
            roomId: room.id,
            iso
          });
          i += len;
        } else {
          cells.push({
            key: room.id + iso,
            isBooking: false,
            colspan: 1,
            roomId: room.id,
            iso,
            cls: isWeekend(iso) ? "pms-free pms-weekend" : "pms-free"
          });
          i += 1;
        }
      }
      return {
        key: room.id,
        id: room.id,
        name: room.name,
        roomType: room.roomType,
        statusCls:
          "pms-room-status pms-room-" +
          (room.status || "").replace(/\s/g, "").toLowerCase(),
        status: room.status,
        cells
      };
    });
  }

  async load() {
    if (!this.siteId) {
      return;
    }
    this.loading = true;
    this.error = undefined;
    try {
      this.data = await getRoomGrid({
        siteId: this.siteId,
        startDate: this.startDate,
        days: this.span
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
    this.startDate = e.detail.value;
    this.load();
  }
  prev() {
    this.startDate = addDays(this.startDate, -7);
    this.load();
  }
  next() {
    this.startDate = addDays(this.startDate, 7);
    this.load();
  }
  goToday() {
    this.startDate = addDays(todayIso(), -1);
    this.load();
  }

  openBooking(e) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: e.currentTarget.dataset.id,
        objectApiName: "PMS_Booking__c",
        actionName: "view"
      }
    });
  }

  handleDragStart(e) {
    this.dragBookingId = e.currentTarget.dataset.id;
    e.dataTransfer.setData("text/plain", this.dragBookingId);
    e.dataTransfer.effectAllowed = "move";
  }
  handleDragOver(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
  }
  async handleDrop(e) {
    e.preventDefault();
    const bookingId =
      this.dragBookingId || e.dataTransfer.getData("text/plain");
    const roomId = e.currentTarget.dataset.room;
    const iso = e.currentTarget.dataset.date;
    this.dragBookingId = undefined;
    if (!bookingId) {
      return;
    }
    this.loading = true;
    try {
      await moveBooking({ bookingId, newSpaceId: roomId, newStartDate: iso });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Booking moved",
          variant: "success",
          message: ""
        })
      );
      await this.load();
    } catch (err) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Could not move booking",
          message: errorMessage(err),
          variant: "error"
        })
      );
      this.loading = false;
    }
  }
}
