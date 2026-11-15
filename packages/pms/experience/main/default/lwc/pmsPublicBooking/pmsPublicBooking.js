import { LightningElement, api, wire } from "lwc";
import getCatalog from "@salesforce/apex/PMS_PublicBookingController.getCatalog";
import searchStays from "@salesforce/apex/PMS_PublicBookingController.searchStays";
import bookStay from "@salesforce/apex/PMS_PublicBookingController.bookStay";
import getAppointmentSlots from "@salesforce/apex/PMS_PublicBookingController.getAppointmentSlots";
import bookAppointment from "@salesforce/apex/PMS_PublicBookingController.bookAppointment";
import submitEnquiry from "@salesforce/apex/PMS_PublicBookingController.submitEnquiry";
import getPayLink from "@salesforce/apex/PMS_PublicBookingController.getPayLink";

const STAY = "stay";
const APPOINTMENT = "appointment";
const HOMES = "homes";

function addDays(isoDate, days) {
  const [y, m, d] = isoDate.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + days));
  return dt.toISOString().slice(0, 10);
}

function errorText(e) {
  if (!e) return "Something went wrong. Please try again.";
  if (e.body && e.body.message) return e.body.message;
  if (Array.isArray(e.body) && e.body.length) return e.body[0].message;
  return e.message || "Something went wrong. Please try again.";
}

export default class PmsPublicBooking extends LightningElement {
  @api heading = "Book online";
  @api intro = "Rooms, appointments and homes to rent. Pay securely by card.";

  catalog;
  loadError;
  mode;

  // Stay search
  hotelId;
  checkIn;
  checkOut;
  adults = 2;
  children = 0;
  stayOptions;
  selectedStay;

  // Appointments
  serviceId;
  practitionerId = "";
  apptDate;
  slotGroups;
  selectedSlot;

  // Homes
  selectedHome;

  // Shared booking flow: browse -> details -> paying | done
  step = "browse";
  guest = { firstName: "", lastName: "", email: "", phone: "", notes: "" };
  honeypot = "";
  detailsOpenedAt = 0;
  busy = false;
  error;
  booking;
  caseNumber;

  @wire(getCatalog)
  wiredCatalog({ data, error }) {
    if (data) {
      this.catalog = data;
      this.loadError = undefined;
      const today = data.today;
      this.checkIn = today;
      this.checkOut = addDays(today, 1);
      this.apptDate = addDays(today, 1);
      if (data.hotels.length) this.hotelId = data.hotels[0].id;
      if (data.services.length) this.serviceId = data.services[0].id;
      this.mode = data.hotels.length
        ? STAY
        : data.services.length
          ? APPOINTMENT
          : data.listings.length
            ? HOMES
            : undefined;
    } else if (error) {
      this.loadError = errorText(error);
    }
  }

  // ------------------------------------------------------------ view state

  get loading() {
    return !this.catalog && !this.loadError;
  }
  get nothingToBook() {
    return this.catalog && !this.mode;
  }
  get modes() {
    if (!this.catalog) return [];
    const list = [];
    if (this.catalog.hotels.length)
      list.push({ key: STAY, label: "Hotel stay" });
    if (this.catalog.services.length)
      list.push({ key: APPOINTMENT, label: "Appointment" });
    if (this.catalog.listings.length)
      list.push({ key: HOMES, label: "Homes to rent" });
    return list.map((m) => ({
      ...m,
      className: "pms-tab" + (m.key === this.mode ? " pms-tab_active" : ""),
      selected: m.key === this.mode ? "true" : "false"
    }));
  }
  get showTabs() {
    return this.modes.length > 1 && this.step === "browse";
  }
  get isBrowse() {
    return this.step === "browse";
  }
  get isDetails() {
    return this.step === "details";
  }
  get isPaying() {
    return this.step === "paying";
  }
  get isDone() {
    return this.step === "done";
  }
  get isStay() {
    return this.mode === STAY;
  }
  get isAppointment() {
    return this.mode === APPOINTMENT;
  }
  get isHomes() {
    return this.mode === HOMES;
  }

  get hotelOptions() {
    return (this.catalog?.hotels || []).map((h) => ({
      label: h.name,
      value: h.id
    }));
  }
  get multipleHotels() {
    return this.hotelOptions.length > 1;
  }
  get selectedHotel() {
    return (this.catalog?.hotels || []).find((h) => h.id === this.hotelId);
  }
  get minCheckOut() {
    return this.checkIn ? addDays(this.checkIn, 1) : undefined;
  }
  get today() {
    return this.catalog?.today;
  }
  get stayResults() {
    if (!this.stayOptions) return undefined;
    return this.stayOptions.map((o) => ({
      ...o,
      soldOut: !o.available,
      fewLeft: o.available > 0 && o.available <= 2,
      totalText: this.money(o.gross, o.currencyCode),
      perNightText: this.money(o.perNight, o.currencyCode),
      nightsText: o.nights === 1 ? "1 night" : `${o.nights} nights`,
      guestsText: o.maxGuests ? `Sleeps ${o.maxGuests}` : ""
    }));
  }
  get noStayResults() {
    return this.stayOptions && this.stayOptions.every((o) => !o.available);
  }

  get serviceOptions() {
    return (this.catalog?.services || []).map((s) => ({
      label: `${s.name} · ${s.minutes} min · ${this.money(s.price, this.catalog.clinicCurrency)}`,
      value: s.id
    }));
  }
  get practitionerOptions() {
    return [{ label: "Anyone available", value: "" }].concat(
      (this.catalog?.practitioners || []).map((p) => ({
        label: p.speciality ? `${p.name} (${p.speciality})` : p.name,
        value: p.id
      }))
    );
  }
  get selectedService() {
    return (this.catalog?.services || []).find((s) => s.id === this.serviceId);
  }
  get maxApptDate() {
    return this.today ? addDays(this.today, 90) : undefined;
  }
  get noSlots() {
    return this.slotGroups && this.slotGroups.length === 0;
  }

  get homes() {
    return (this.catalog?.listings || []).map((l) => ({
      ...l,
      rentText: l.rent
        ? `${this.money(l.rent, l.currencyCode)} / month`
        : "Rent on request",
      facts: [
        l.bedrooms != null
          ? `${l.bedrooms} bedroom${l.bedrooms === 1 ? "" : "s"}`
          : null,
        l.sizeSqm ? `${l.sizeSqm} m²` : null,
        l.floor ? `Floor ${l.floor}` : null
      ]
        .filter(Boolean)
        .join(" · "),
      amenityText: (l.amenities || []).join(", ")
    }));
  }

  get summaryTitle() {
    if (this.mode === STAY && this.selectedStay) return this.selectedStay.name;
    if (this.mode === APPOINTMENT && this.selectedService)
      return this.selectedService.name;
    if (this.mode === HOMES && this.selectedHome)
      return `Viewing request: ${this.selectedHome.name}`;
    return "";
  }
  get summaryLines() {
    if (this.mode === STAY && this.selectedStay) {
      const h = this.selectedHotel;
      return [
        h ? h.name : "",
        `${this.checkIn} to ${this.checkOut} (${this.selectedStay.nightsText})`,
        `${this.adults} adult${this.adults === 1 ? "" : "s"}${this.children ? `, ${this.children} child${this.children === 1 ? "" : "ren"}` : ""}`,
        h && h.checkIn
          ? `Check-in from ${h.checkIn}, check-out by ${h.checkOut}`
          : null
      ].filter(Boolean);
    }
    if (this.mode === APPOINTMENT && this.selectedSlot) {
      return [
        `${this.selectedSlot.dayText} at ${this.selectedSlot.label}`,
        `with ${this.selectedSlot.practitionerName}`,
        `${this.selectedService.minutes} minutes`
      ];
    }
    if (this.mode === HOMES && this.selectedHome) {
      return [
        this.selectedHome.siteName,
        this.selectedHome.facts,
        this.selectedHome.rentText
      ].filter(Boolean);
    }
    return [];
  }
  get summaryTotal() {
    if (this.mode === STAY && this.selectedStay)
      return this.selectedStay.totalText;
    if (this.mode === APPOINTMENT && this.selectedService)
      return this.money(
        this.selectedService.price,
        this.catalog.clinicCurrency
      );
    return null;
  }
  get cancellationPolicy() {
    return this.mode === STAY && this.selectedStay
      ? this.selectedStay.cancellationPolicy
      : null;
  }
  get isEnquiry() {
    return this.mode === HOMES;
  }
  get submitLabel() {
    return this.isEnquiry ? "Send request" : "Continue to secure payment";
  }
  get notesLabel() {
    return this.isEnquiry
      ? "Message (when would you like to view?)"
      : "Special requests (optional)";
  }
  get bookingAmountText() {
    return this.booking
      ? this.money(this.booking.amount, this.booking.currencyCode)
      : "";
  }

  money(amount, currencyCode) {
    if (amount === null || amount === undefined) return "";
    try {
      return new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: currencyCode || "SEK",
        maximumFractionDigits: Number(amount) % 1 === 0 ? 0 : 2
      }).format(amount);
    } catch {
      return `${amount} ${currencyCode || ""}`.trim();
    }
  }

  // ------------------------------------------------------------ navigation

  handleMode(event) {
    this.mode = event.currentTarget.dataset.mode;
    this.error = undefined;
  }

  backToBrowse() {
    this.step = "browse";
    this.error = undefined;
    this.booking = undefined;
  }

  openDetails() {
    this.step = "details";
    this.error = undefined;
    this.detailsOpenedAt = Date.now();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      const first = this.template.querySelector(
        'lightning-input[data-field="firstName"]'
      );
      if (first) first.focus();
    });
  }

  // ------------------------------------------------------------ stays

  handleStayField(event) {
    const field = event.target.dataset.field;
    let value = event.detail.value;
    if (field === "adults" || field === "children")
      value = parseInt(value, 10) || 0;
    this[field] = value;
    if (field === "checkIn" && this.checkOut <= value)
      this.checkOut = addDays(value, 1);
    this.stayOptions = undefined;
  }

  async handleSearchStays() {
    this.error = undefined;
    if (!this.validate(".pms-stay-search")) return;
    this.busy = true;
    try {
      this.stayOptions = await searchStays({
        siteId: this.hotelId,
        checkIn: this.checkIn,
        checkOut: this.checkOut,
        guests: this.adults + this.children
      });
    } catch (e) {
      this.error = errorText(e);
      this.stayOptions = undefined;
    } finally {
      this.busy = false;
    }
  }

  handleChooseStay(event) {
    const id = event.currentTarget.dataset.id;
    this.selectedStay = this.stayResults.find((o) => o.spaceTypeId === id);
    this.openDetails();
  }

  // ------------------------------------------------------------ appointments

  handleApptField(event) {
    this[event.target.dataset.field] = event.detail.value;
    this.slotGroups = undefined;
  }

  async handleFindSlots() {
    this.error = undefined;
    if (!this.validate(".pms-appt-search")) return;
    this.busy = true;
    try {
      const slots = await getAppointmentSlots({
        serviceId: this.serviceId,
        practitionerId: this.practitionerId || null,
        day: this.apptDate
      });
      const dayText = new Date(`${this.apptDate}T12:00:00`).toLocaleDateString(
        undefined,
        {
          weekday: "long",
          day: "numeric",
          month: "long"
        }
      );
      const groups = new Map();
      slots.forEach((s, i) => {
        if (!groups.has(s.practitionerId)) {
          groups.set(s.practitionerId, {
            key: s.practitionerId,
            name: s.practitionerName,
            slots: []
          });
        }
        groups.get(s.practitionerId).slots.push({
          ...s,
          key: `${s.practitionerId}-${i}`,
          index: i,
          dayText
        });
      });
      this.slotGroups = Array.from(groups.values());
    } catch (e) {
      this.error = errorText(e);
      this.slotGroups = undefined;
    } finally {
      this.busy = false;
    }
  }

  handleChooseSlot(event) {
    const key = event.currentTarget.dataset.key;
    for (const g of this.slotGroups) {
      const found = g.slots.find((s) => s.key === key);
      if (found) {
        this.selectedSlot = found;
        break;
      }
    }
    this.openDetails();
  }

  // ------------------------------------------------------------ homes

  handleChooseHome(event) {
    const id = event.currentTarget.dataset.id;
    this.selectedHome = this.homes.find((h) => h.id === id);
    this.openDetails();
  }

  // ------------------------------------------------------------ details + submit

  handleGuestField(event) {
    this.guest = {
      ...this.guest,
      [event.target.dataset.field]: event.detail.value
    };
  }

  handleHoneypot(event) {
    this.honeypot = event.target.value;
  }

  get guestJson() {
    return JSON.stringify({
      ...this.guest,
      website: this.honeypot,
      elapsedMs: Date.now() - this.detailsOpenedAt
    });
  }

  async handleSubmit() {
    this.error = undefined;
    if (!this.validate(".pms-details")) return;
    this.busy = true;
    try {
      if (this.mode === HOMES) {
        this.caseNumber = await submitEnquiry({
          unitId: this.selectedHome.id,
          guestJson: this.guestJson
        });
        this.step = "done";
        return;
      }
      if (this.mode === STAY) {
        this.booking = await bookStay({
          siteId: this.hotelId,
          spaceTypeId: this.selectedStay.spaceTypeId,
          checkIn: this.checkIn,
          checkOut: this.checkOut,
          adults: this.adults,
          children: this.children,
          guestJson: this.guestJson
        });
      } else {
        this.booking = await bookAppointment({
          serviceId: this.serviceId,
          practitionerId: this.selectedSlot.practitionerId,
          startAt: this.selectedSlot.startAt,
          guestJson: this.guestJson
        });
      }
      this.step = "paying";
      await this.goToPayment();
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.busy = false;
    }
  }

  async goToPayment() {
    this.error = undefined;
    this.busy = true;
    try {
      const link = await getPayLink({
        bookingId: this.booking.bookingId,
        accessKey: this.booking.accessKey
      });
      window.location.assign(link.url);
    } catch (e) {
      this.error = errorText(e);
      this.busy = false;
    }
  }

  validate(selector) {
    const container = this.template.querySelector(selector);
    if (!container) return true;
    const inputs = [
      ...container.querySelectorAll(
        "lightning-input, lightning-combobox, lightning-textarea"
      )
    ];
    return inputs.reduce((ok, input) => input.reportValidity() && ok, true);
  }
}
