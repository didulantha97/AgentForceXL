import { LightningElement, api } from "lwc";

const ID_TYPES = [
  { label: "Passport", value: "Passport" },
  { label: "National ID card", value: "National ID Card" },
  { label: "Driving licence", value: "Driving Licence" }
];

/**
 * Online check-in form for one booking (hotel stay, clinic questionnaire or move-in).
 * Used by pmsCustomerPortalV2 and pmsGuestCheckIn. Fires "checkinsubmit" with { bookingId, formJson };
 * the parent calls Apex and passes errors back through the error property.
 */
export default class PmsCheckInForm extends LightningElement {
  @api busy = false;
  @api error;
  values = {};
  readings = {};
  _checkIn;

  @api
  get checkIn() {
    return this._checkIn;
  }
  set checkIn(value) {
    this._checkIn = value;
    if (value) {
      this.values = {
        fullName: value.fullName || "",
        phone: value.phone || "",
        guests: value.guests || 1,
        moveInDate: value.startDate || "",
        answers: {}
      };
      this.readings = {};
    }
  }

  get isHotel() {
    return this._checkIn && this._checkIn.kind === "hotel";
  }
  get isClinic() {
    return this._checkIn && this._checkIn.kind === "clinic";
  }
  get isMoveIn() {
    return this._checkIn && this._checkIn.kind === "movein";
  }
  get idTypes() {
    return ID_TYPES;
  }
  get submitLabel() {
    if (this.isClinic) return "Send questionnaire";
    if (this.isMoveIn) return "Send move-in details";
    return "Check in";
  }
  get hasMeters() {
    return (
      this.isMoveIn && this._checkIn.meters && this._checkIn.meters.length > 0
    );
  }
  get meters() {
    return (this._checkIn.meters || []).map((m) => ({
      ...m,
      label: m.name + (m.meterType ? " (" + m.meterType + ")" : ""),
      help:
        m.lastReading !== null && m.lastReading !== undefined
          ? "Last reading: " + m.lastReading
          : ""
    }));
  }
  get questions() {
    return (this._checkIn.questions || []).map((q) => ({
      ...q,
      isText: q.type === "text",
      isTextarea: q.type === "textarea",
      isSelect: q.type === "select",
      options: (q.options || []).map((o) => ({ label: o, value: o }))
    }));
  }

  handleValue(event) {
    const field = event.target.dataset.field;
    const value =
      event.target.type === "checkbox" || event.target.type === "toggle"
        ? event.target.checked
        : event.detail.value;
    this.values = { ...this.values, [field]: value };
  }

  handleAnswer(event) {
    const key = event.target.dataset.key;
    this.values = {
      ...this.values,
      answers: { ...this.values.answers, [key]: event.detail.value }
    };
  }

  handleReading(event) {
    this.readings = {
      ...this.readings,
      [event.target.dataset.id]: event.detail.value
    };
  }

  submit() {
    const inputs = [
      ...this.template.querySelectorAll(
        "lightning-input, lightning-textarea, lightning-combobox"
      )
    ];
    const valid = inputs.reduce((ok, el) => el.reportValidity() && ok, true);
    if (!valid) return;
    const v = this.values;
    let form;
    if (this.isClinic) {
      form = {
        answers: v.answers,
        consentTreatment: v.consentTreatment === true,
        consentData: v.consentData === true
      };
    } else {
      form = {
        fullName: v.fullName,
        phone: v.phone,
        arrivalTime: v.arrivalTime ? String(v.arrivalTime).slice(0, 5) : null,
        guests: v.guests ? Number(v.guests) : null,
        nationality: v.nationality,
        dateOfBirth: v.dateOfBirth,
        address: v.address,
        idType: v.idType,
        idNumber: v.idNumber,
        vehicle: v.vehicle,
        requests: v.requests,
        terms: v.terms === true,
        moveInDate: v.moveInDate,
        occupants: v.occupants ? Number(v.occupants) : null,
        emergencyContact: v.emergencyContact,
        readings: Object.keys(this.readings)
          .filter(
            (id) => this.readings[id] !== "" && this.readings[id] !== null
          )
          .map((id) => ({ meterId: id, value: Number(this.readings[id]) }))
      };
    }
    this.dispatchEvent(
      new CustomEvent("checkinsubmit", {
        detail: {
          bookingId: this._checkIn.bookingId,
          formJson: JSON.stringify(form)
        }
      })
    );
  }
}
