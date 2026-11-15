/**
 * Date helpers shared by the PMS components. Dates are handled as 'YYYY-MM-DD'
 * strings and calculated in UTC so a user's browser time zone never shifts a day.
 */
const DAY_MS = 86400000;
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export function parseIso(iso) {
  if (!iso) {
    return null;
  }
  const [y, m, d] = iso.substring(0, 10).split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}

export function toIso(ms) {
  return new Date(ms).toISOString().substring(0, 10);
}

export function addDays(iso, n) {
  return toIso(parseIso(iso) + n * DAY_MS);
}

export function daysBetween(fromIso, toIsoStr) {
  return Math.round((parseIso(toIsoStr) - parseIso(fromIso)) / DAY_MS);
}

export function todayIso() {
  const now = new Date();
  return toIso(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
}

export function weekdayShort(iso) {
  return WEEKDAYS[new Date(parseIso(iso)).getUTCDay()];
}

export function mondayOf(iso) {
  const day = new Date(parseIso(iso)).getUTCDay();
  const shift = day === 0 ? -6 : 1 - day;
  return addDays(iso, shift);
}

export function isWeekend(iso) {
  const day = new Date(parseIso(iso)).getUTCDay();
  return day === 0 || day === 6;
}

export function errorMessage(error) {
  if (!error) {
    return "Unknown error";
  }
  if (Array.isArray(error.body)) {
    return error.body.map((e) => e.message).join(", ");
  }
  if (error.body && error.body.message) {
    return error.body.message;
  }
  return error.message || String(error);
}
