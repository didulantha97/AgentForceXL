import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import getCheckIn from "@salesforce/apex/PMS_GuestCheckInController.getCheckIn";
import submitCheckIn from "@salesforce/apex/PMS_GuestCheckInController.submitCheckIn";

function errorText(e) {
  if (!e) return "Something went wrong.";
  if (e.body && e.body.message) return e.body.message;
  return e.message || String(e);
}

/**
 * Online check-in from the emailed link on the public booking site: /book?checkin=<booking id>&key=<secret>.
 * Renders nothing when the page has no check-in link, so it can sit on the booking site's home page.
 */
export default class PmsGuestCheckIn extends LightningElement {
  bookingId;
  key;
  view;
  loading = false;
  busy = false;
  error;
  formError;
  done = false;

  @wire(CurrentPageReference)
  pageRef(ref) {
    const state = (ref && ref.state) || {};
    let id = state.checkin;
    let key = state.key;
    if (!id && typeof window !== "undefined") {
      const params = new URLSearchParams(window.location.search);
      id = params.get("checkin");
      key = params.get("key");
    }
    if (id && key && id !== this.bookingId) {
      this.bookingId = id;
      this.key = key;
      this.load();
    }
  }

  get active() {
    return !!this.bookingId;
  }
  get checkIn() {
    return this.view ? this.view.checkIn : null;
  }
  get showForm() {
    return this.checkIn && !this.checkIn.done && !this.done;
  }
  get isDone() {
    return this.done || (this.checkIn && this.checkIn.done);
  }
  get heading() {
    if (!this.checkIn) return "Online check-in";
    return this.checkIn.kind === "clinic"
      ? "Before your appointment"
      : this.checkIn.kind === "movein"
        ? "Before you move in"
        : "Online check-in";
  }

  async load() {
    this.loading = true;
    this.error = undefined;
    try {
      this.view = await getCheckIn({
        bookingId: this.bookingId,
        key: this.key
      });
      if (this.view.message) this.error = this.view.message;
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.loading = false;
    }
  }

  async handleSubmit(event) {
    this.busy = true;
    this.formError = undefined;
    try {
      this.view = await submitCheckIn({
        bookingId: this.bookingId,
        key: this.key,
        formJson: event.detail.formJson
      });
      this.done = true;
    } catch (e) {
      this.formError = errorText(e);
    } finally {
      this.busy = false;
    }
  }
}
