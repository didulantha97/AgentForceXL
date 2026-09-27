import { LightningElement, track } from "lwc";
import { getCalendarService } from "lightning/mobileCapabilities";

const CALENDAR_OPTIONS = {
  permissionRationaleText: "Allow calendar access to view and add events."
};

const FAILURE_MESSAGES = {
  USER_DENIED_PERMISSION:
    "Calendar permission was denied. Try again and allow access when prompted.",
  NOT_FOUND:
    "The calendar or event could not be found. It may have been deleted.",
  SERVICE_NOT_ENABLED: "The calendar service is not enabled for this app."
};

const DAYS_AHEAD = 7;
const ALARM_OFFSET_SECONDS = -15 * 60; // 15 minutes before the event starts
const ALL_CALENDARS = "";

export default class CalendarComponent extends LightningElement {
  @track calendars = [];
  @track events = [];
  @track selectedCalendarId = ALL_CALENDARS;
  @track form = this._emptyForm();
  @track errorMessage = "";
  @track successMessage = "";
  @track isBusy = false;
  @track hasLoaded = false;

  _calendar = null;
  _rawEvents = [];

  connectedCallback() {
    this._calendar = getCalendarService();
  }

  get isAvailable() {
    return this._calendar != null && this._calendar.isAvailable();
  }

  get calendarFilterOptions() {
    return [
      { label: "All calendars", value: ALL_CALENDARS },
      ...this.calendars.map((cal) => ({ label: cal.title, value: cal.id }))
    ];
  }

  get writableCalendarOptions() {
    return this.calendars
      .filter((cal) => cal.allowsContentModifications)
      .map((cal) => ({ label: cal.title, value: cal.id }));
  }

  get hasEvents() {
    return this.events.length > 0;
  }

  get showNoEvents() {
    return this.hasLoaded && !this.hasEvents;
  }

  get isAddDisabled() {
    const { title, start, end, calendarId } = this.form;
    return this.isBusy || !title.trim() || !start || !end || !calendarId;
  }

  async handleLoad() {
    await this._run(async () => {
      this.calendars = await this._calendar.getCalendars(CALENDAR_OPTIONS);
      if (!this.form.calendarId) {
        const primary = this.calendars.find(
          (cal) => cal.isPrimary && cal.allowsContentModifications
        );
        this.form = { ...this.form, calendarId: primary ? primary.id : "" };
      }
      await this._loadEvents();
    });
  }

  async handleCalendarFilterChange(event) {
    this.selectedCalendarId = event.detail.value;
    await this._run(() => this._loadEvents());
  }

  handleFieldChange(event) {
    const field = event.target.dataset.field;
    const value =
      event.target.type === "checkbox"
        ? event.detail.checked
        : event.detail.value;
    this.form = { ...this.form, [field]: value };
  }

  async handleAdd() {
    const { title, start, end, location, calendarId, isAllDay, addAlarm } =
      this.form;
    const startSeconds = Math.floor(Date.parse(start) / 1000);
    const endSeconds = Math.floor(Date.parse(end) / 1000);
    if (endSeconds <= startSeconds) {
      this.errorMessage = "The end time must be after the start time.";
      this.successMessage = "";
      return;
    }

    await this._run(async () => {
      await this._calendar.addEvent(
        {
          id: "",
          title: title.trim(),
          isAllDay,
          startDateSecondsUTC: startSeconds,
          endDateSecondsUTC: endSeconds,
          availability: "Busy",
          status: "Confirmed",
          calendarId,
          location: location.trim(),
          alarms: addAlarm
            ? [{ relativeOffsetSeconds: ALARM_OFFSET_SECONDS }]
            : []
        },
        CALENDAR_OPTIONS
      );
      this.successMessage = `"${title.trim()}" was added to your calendar.`;
      this.form = { ...this._emptyForm(), calendarId };
      await this._loadEvents();
    });
  }

  async handleRemove(event) {
    const eventId = event.currentTarget.dataset.id;
    const target = this._rawEvents.find((e) => e.id === eventId);
    if (!target) {
      return;
    }
    await this._run(async () => {
      await this._calendar.removeEvent(target, {
        ...CALENDAR_OPTIONS,
        span: "ThisEvent"
      });
      this.successMessage = `"${target.title}" was removed from your calendar.`;
      await this._loadEvents();
    });
  }

  async _loadEvents() {
    const now = new Date();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const end = new Date(start.getTime() + DAYS_AHEAD * 24 * 60 * 60 * 1000);
    const selected = this.calendars.find(
      (cal) => cal.id === this.selectedCalendarId
    );

    const events = await this._calendar.getEvents(
      Math.floor(start.getTime() / 1000),
      Math.floor(end.getTime() / 1000),
      selected ? [selected.title] : null,
      CALENDAR_OPTIONS
    );

    const colorById = new Map(
      this.calendars.map((cal) => [cal.id, cal.hexColor])
    );
    const writableIds = new Set(
      this.calendars
        .filter((cal) => cal.allowsContentModifications)
        .map((cal) => cal.id)
    );

    this._rawEvents = (events || [])
      .slice()
      .sort((a, b) => a.startDateSecondsUTC - b.startDateSecondsUTC);
    this.events = this._rawEvents.map((evt, index) => ({
      key: `${index}-${evt.id}`,
      id: evt.id,
      title: evt.title || "(No title)",
      when: this._formatWhen(evt),
      location: evt.location,
      canRemove: writableIds.has(evt.calendarId),
      colorStyle: `background-color: ${colorById.get(evt.calendarId) || "#747474"};`
    }));
    this.hasLoaded = true;
  }

  async _run(operation) {
    this.errorMessage = "";
    this.successMessage = "";
    this.isBusy = true;
    try {
      await operation();
    } catch (error) {
      this.errorMessage = this._formatError(error);
    } finally {
      this.isBusy = false;
    }
  }

  _formatWhen(evt) {
    const start = new Date(evt.startDateSecondsUTC * 1000);
    const end = new Date(evt.endDateSecondsUTC * 1000);
    const day = start.toLocaleDateString(undefined, {
      weekday: "short",
      month: "short",
      day: "numeric"
    });
    if (evt.isAllDay) {
      return `${day} · All day`;
    }
    const timeOptions = { hour: "numeric", minute: "2-digit" };
    return `${day} · ${start.toLocaleTimeString(undefined, timeOptions)} – ${end.toLocaleTimeString(undefined, timeOptions)}`;
  }

  _emptyForm() {
    return {
      title: "",
      start: "",
      end: "",
      location: "",
      calendarId: "",
      isAllDay: false,
      addAlarm: true
    };
  }

  _formatError(error) {
    if (error && FAILURE_MESSAGES[error.code]) {
      return FAILURE_MESSAGES[error.code];
    }
    return (
      (error && error.message) ||
      "An unknown error occurred while accessing your calendar."
    );
  }
}
