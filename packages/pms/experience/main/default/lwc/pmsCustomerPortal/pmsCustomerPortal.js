import { LightningElement, api } from "lwc";
import getContext from "@salesforce/apex/PMS_PortalController.getContext";
import getBookings from "@salesforce/apex/PMS_PortalController.getBookings";
import getInvoices from "@salesforce/apex/PMS_PortalController.getInvoices";
import getRequests from "@salesforce/apex/PMS_PortalController.getRequests";
import payInvoice from "@salesforce/apex/PMS_PortalController.payInvoice";
import createRequest from "@salesforce/apex/PMS_PortalController.createRequest";

const STATUS_THEME = {
  Paid: "success",
  Active: "success",
  Confirmed: "success",
  "Checked In": "success",
  Closed: "success",
  Completed: "neutral",
  Overdue: "error",
  Escalated: "error",
  Critical: "error",
  Cancelled: "neutral",
  Void: "neutral"
};

function errorText(error) {
  if (!error) {
    return "Something went wrong.";
  }
  if (error.body && error.body.message) {
    return error.body.message;
  }
  return error.message || "Something went wrong.";
}

function badgeClass(status) {
  const theme = STATUS_THEME[status] || "info";
  return `pill pill_${theme}`;
}

/**
 * PMS Customer Portal: one component with Overview, Bookings, Invoices and Requests tabs.
 * Built for the "PMS Customer Portal" LWR site. Uses inline messages instead of toasts,
 * because toast events are not supported on LWR sites.
 */
export default class PmsCustomerPortal extends LightningElement {
  @api defaultTab = "overview";
  @api showHeader = false;

  activeTab = "overview";
  loading = true;
  error;
  notice;
  context;
  bookings = [];
  invoices = [];
  requests = [];
  payingId;

  // new request form
  showForm = false;
  subject = "";
  description = "";
  bookingId = "";
  entryPermission = false;
  saving = false;
  formError;

  connectedCallback() {
    this.activeTab = this.defaultTab || "overview";
    this.loadAll();
  }

  async loadAll() {
    this.loading = true;
    this.error = undefined;
    try {
      const [ctx, bookings, invoices, requests] = await Promise.all([
        getContext(),
        getBookings(),
        getInvoices(),
        getRequests()
      ]);
      this.context = ctx;
      this.bookings = bookings.map((b) => ({
        ...b,
        badge: badgeClass(b.status),
        hasBalance: b.balance > 0
      }));
      this.invoices = invoices.map((i) => ({
        ...i,
        badge: badgeClass(
          i.daysOverdue > 0 && i.payable ? "Overdue" : i.status
        ),
        statusLabel:
          i.daysOverdue > 0 && i.payable
            ? `Overdue ${i.daysOverdue} d`
            : i.status,
        isPaying: false
      }));
      this.requests = requests.map((r) => ({
        ...r,
        badge: badgeClass(r.status)
      }));
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.loading = false;
    }
  }

  // ---------- getters ----------

  get greeting() {
    return this.context && this.context.firstName
      ? `Welcome, ${this.context.firstName}`
      : "Welcome";
  }
  get currency() {
    return (this.context && this.context.currencyCode) || "SEK";
  }
  get hasBookings() {
    return this.bookings.length > 0;
  }
  get hasInvoices() {
    return this.invoices.length > 0;
  }
  get hasRequests() {
    return this.requests.length > 0;
  }
  get openInvoices() {
    return this.invoices.filter((i) => i.payable);
  }
  get hasOpenInvoices() {
    return this.openInvoices.length > 0;
  }
  get upcomingBookings() {
    const now = Date.now();
    return this.bookings
      .filter((b) => !b.endAt || new Date(b.endAt).getTime() >= now)
      .slice(0, 3);
  }
  get hasUpcoming() {
    return this.upcomingBookings.length > 0;
  }
  get overdueClass() {
    return this.context && this.context.overdueInvoices > 0
      ? "tile tile_alert"
      : "tile";
  }
  get bookingOptions() {
    return [{ label: "Not about a specific booking", value: "" }].concat(
      this.bookings.map((b) => ({ label: b.label, value: b.id }))
    );
  }
  get selectedIsLease() {
    const b = this.bookings.find((x) => x.id === this.bookingId);
    return b && b.kind === "Lease";
  }
  get showNewButton() {
    return !this.showForm;
  }
  get submitDisabled() {
    return this.saving || !this.subject || !this.subject.trim();
  }

  // ---------- handlers ----------

  handleTab(event) {
    this.activeTab = event.target.value;
  }

  goInvoices() {
    this.activeTab = "invoices";
  }
  goRequests() {
    this.activeTab = "requests";
  }
  goBookings() {
    this.activeTab = "bookings";
  }

  async handlePay(event) {
    const id = event.currentTarget.dataset.id;
    this.notice = undefined;
    this.error = undefined;
    this.payingId = id;
    this.invoices = this.invoices.map((i) => ({ ...i, isPaying: i.id === id }));
    try {
      const link = await payInvoice({ invoiceId: id });
      window.location.assign(link.url);
    } catch (e) {
      this.error = errorText(e);
      this.invoices = this.invoices.map((i) => ({ ...i, isPaying: false }));
    } finally {
      this.payingId = undefined;
    }
  }

  openForm() {
    this.showForm = true;
    this.formError = undefined;
    this.notice = undefined;
  }
  cancelForm() {
    this.showForm = false;
    this.resetForm();
  }
  resetForm() {
    this.subject = "";
    this.description = "";
    this.bookingId = "";
    this.entryPermission = false;
    this.formError = undefined;
  }
  handleSubject(e) {
    this.subject = e.target.value;
  }
  handleDescription(e) {
    this.description = e.target.value;
  }
  handleBooking(e) {
    this.bookingId = e.detail.value;
    if (!this.selectedIsLease) {
      this.entryPermission = false;
    }
  }
  handleEntry(e) {
    this.entryPermission = e.target.checked;
  }

  async submitRequest() {
    this.saving = true;
    this.formError = undefined;
    try {
      const caseNumber = await createRequest({
        subject: this.subject,
        description: this.description,
        bookingId: this.bookingId || null,
        entryPermission: this.entryPermission
      });
      this.notice = `Thanks. Your request ${caseNumber} has been logged and our team will be in touch.`;
      this.showForm = false;
      this.resetForm();
      const [ctx, requests] = await Promise.all([getContext(), getRequests()]);
      this.context = ctx;
      this.requests = requests.map((r) => ({
        ...r,
        badge: badgeClass(r.status)
      }));
    } catch (e) {
      this.formError = errorText(e);
    } finally {
      this.saving = false;
    }
  }

  dismissNotice() {
    this.notice = undefined;
  }
}
