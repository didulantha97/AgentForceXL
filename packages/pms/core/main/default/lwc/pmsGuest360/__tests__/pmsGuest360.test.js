import { createElement } from "lwc";
import PmsGuest360 from "c/pmsGuest360";
import getGuest360 from "@salesforce/apex/PMS_Guest360Controller.getGuest360";
import { refreshApex } from "@salesforce/apex";
import fixture from "./data/guest360.json";

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PMS_Guest360Controller.getGuest360",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const mockNavigate = jest.fn();
jest.mock(
  "lightning/navigation",
  () => {
    const Navigate = Symbol("Navigate");
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          return global.__mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
  },
  { virtual: true }
);
global.__mockNavigate = (...a) => mockNavigate(...a);

const flush = () => Promise.resolve();
const clone = (o) => JSON.parse(JSON.stringify(o));

function mount(recordId = "003000000000001AAA") {
  const el = createElement("c-pms-guest-360", { is: PmsGuest360 });
  if (recordId) {
    el.recordId = recordId;
  }
  document.body.appendChild(el);
  return el;
}
const q = (el, sel) => el.shadowRoot.querySelector(sel);
const qa = (el, sel) => [...el.shadowRoot.querySelectorAll(sel)];
const tabLabels = (el) => qa(el, "lightning-tab").map((t) => t.label);
const text = (el) => el.shadowRoot.textContent.replace(/\s+/g, " ");

describe("c-pms-guest-360", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows no-record message and no spinner without recordId", async () => {
    const el = mount(null);
    await flush();
    expect(text(el)).toContain("Open this component on a Contact record");
    expect(q(el, "lightning-spinner")).toBeNull();
  });

  it("shows spinner while loading", async () => {
    const el = mount();
    await flush();
    expect(q(el, "lightning-spinner")).not.toBeNull();
    expect(q(el, "h2")).toBeNull();
  });

  it("renders header, badges and KPIs from wire data", async () => {
    const el = mount();
    getGuest360.emit(clone(fixture));
    await flush();
    expect(q(el, "lightning-spinner")).toBeNull();
    expect(q(el, "h2").textContent).toBe("Ada Lovelace");
    expect(text(el)).toContain("VIP: Gold");
    expect(text(el)).toContain("ID verified");
    expect(text(el)).toContain("English");
    expect(text(el)).toContain("Analytical Ltd");
    expect(text(el)).toContain("Prefers high floor");
    const kpis = qa(el, ".kpi");
    expect(kpis).toHaveLength(7);
    expect(kpis[0].textContent).toContain("Total stays");
    expect(q(el, ".kpi lightning-formatted-number").value).toBe(5);
    // next arrival null renders "None"
    expect(kpis[6].textContent).toContain("None");
    expect(kpis[6].textContent).toContain("Next arrival");
  });

  it("hides VIP badge and shows ID not verified", async () => {
    const d = clone(fixture);
    d.identity.vipLevel = null;
    d.identity.idVerified = false;
    const el = mount();
    getGuest360.emit(d);
    await flush();
    expect(text(el)).not.toContain("VIP:");
    expect(text(el)).toContain("ID not verified");
  });

  it("renders all tabs with counts when accessible", async () => {
    const el = mount();
    getGuest360.emit(clone(fixture));
    await flush();
    expect(tabLabels(el)).toEqual([
      "Upcoming stays (2)",
      "Past stays (2)",
      "Preferences",
      "Service (2)",
      "Consent"
    ]);
  });

  it.each([
    ["upcomingStays", "Upcoming stays (2)"],
    ["pastStays", "Past stays (2)"],
    ["preferences", "Preferences"],
    ["service", "Service (2)"],
    ["consent", "Consent"]
  ])("hides the tab when %s is not accessible", async (key, label) => {
    const d = clone(fixture);
    d[key].accessible = false;
    const el = mount();
    getGuest360.emit(d);
    await flush();
    expect(tabLabels(el)).not.toContain(label);
    expect(tabLabels(el)).toHaveLength(4);
  });

  it("hides KPIs when stats not accessible", async () => {
    const d = clone(fixture);
    d.stats.accessible = false;
    const el = mount();
    getGuest360.emit(d);
    await flush();
    expect(qa(el, ".kpi")).toHaveLength(0);
  });

  it("shows empty-state text for accessible empty sections", async () => {
    const d = clone(fixture);
    d.upcomingStays.items = [];
    d.pastStays.items = [];
    d.preferences.items = [];
    d.identity.dietary = null;
    d.identity.accessibilityNeeds = null;
    d.service.items = [];
    d.consent.formAccessible = true;
    d.consent.gdprFormDate = null;
    const el = mount();
    getGuest360.emit(d);
    await flush();
    const t = text(el);
    expect(t).toContain("No upcoming stays.");
    expect(t).toContain("No past stays.");
    expect(t).toContain("No preferences recorded.");
    expect(t).toContain("No service cases.");
    expect(t).toContain("No GDPR form on file.");
  });

  it("shows error message from wire error and no content", async () => {
    const el = mount();
    getGuest360.error({ message: "x" });
    await flush();
    const alert = q(el, '[role="alert"]');
    expect(alert.textContent).toContain("x");
    expect(q(el, "lightning-spinner")).toBeNull();
    expect(q(el, "h2")).toBeNull();
  });

  it("shows a different wire error message", async () => {
    const el = mount();
    getGuest360.error({ message: "No access" });
    await flush();
    expect(q(el, '[role="alert"]').textContent).toContain("No access");
  });

  it("refresh button calls refreshApex", async () => {
    const el = mount();
    getGuest360.emit(clone(fixture));
    await flush();
    q(el, "lightning-button-icon").click();
    await flush();
    expect(refreshApex).toHaveBeenCalledTimes(1);
  });

  it.each([
    ["booking", "a01000000000001AAA"],
    ["booking (past)", "a01000000000002AAA"],
    ["case", "500000000000001AAA"]
  ])("navigates to %s record on link click", async (_n, id) => {
    const el = mount();
    getGuest360.emit(clone(fixture));
    await flush();
    const link = qa(el, "a[data-id]").find((a) => a.dataset.id === id);
    link.click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: { recordId: id, actionName: "view" }
    });
  });

  it("groups preferences with dietary/accessibility first and shows highlights", async () => {
    const el = mount();
    getGuest360.emit(clone(fixture));
    await flush();
    const headings = qa(el, "h3.slds-grid").map((h) => h.textContent.trim());
    // Food & Drink is promoted; other groups keep insertion order
    expect(headings).toEqual([
      "Food & Drink",
      "Room",
      "Other",
      "Accessibility"
    ]);
    const boxes = qa(el, ".pref-highlight");
    expect(boxes).toHaveLength(2);
    expect(boxes[0].textContent).toContain("Dietary");
    expect(boxes[0].textContent).toContain("Vegan");
    expect(boxes[1].textContent).toContain("Accessibility needs");
    expect(boxes[1].textContent).toContain("Step-free access");
    expect(text(el)).toContain("Quiet room");
    expect(text(el)).toContain("(Guest)");
  });

  it("shows Food & Drink group first with its icon", async () => {
    const el = mount();
    getGuest360.emit(clone(fixture));
    await flush();
    const first = qa(el, "h3.slds-grid")[0];
    expect(first.textContent).toContain("Food & Drink");
    expect(first.querySelector("lightning-icon").iconName).toBe(
      "utility:food_and_drink"
    );
    expect(text(el)).toContain("No nuts");
  });

  it("party-only stay shows via party label and hides amounts and requests", async () => {
    const el = mount();
    getGuest360.emit(clone(fixture));
    await flush();
    const rows = qa(el, ".stay-row");
    const party = rows.find((r) => r.textContent.includes("BK-0004"));
    expect(party.textContent).toContain("via party booking");
    expect(party.textContent).not.toContain("Balance due");
    expect(party.textContent).not.toContain("Party secret");
    expect(party.querySelector("lightning-formatted-number")).toBeNull();
    const direct = rows.find((r) => r.textContent.includes("BK-0001"));
    expect(direct.textContent).not.toContain("via party booking");
    expect(direct.textContent).toContain("Balance due");
    expect(direct.textContent).toContain("Late arrival");
  });

  it("hides refresh button with no record", async () => {
    const el = mount(null);
    await flush();
    expect(q(el, "lightning-button-icon")).toBeNull();
  });

  it("resets to loading when recordId changes", async () => {
    const el = mount();
    getGuest360.emit(clone(fixture));
    await flush();
    expect(q(el, "h2")).not.toBeNull();
    el.recordId = "003000000000002AAA";
    await flush();
    await flush();
    expect(q(el, "h2")).toBeNull();
    expect(q(el, "lightning-spinner")).not.toBeNull();
  });

  it("omits highlight boxes when identity has no dietary/accessibility", async () => {
    const d = clone(fixture);
    d.identity.dietary = null;
    d.identity.accessibilityNeeds = null;
    const el = mount();
    getGuest360.emit(d);
    await flush();
    expect(qa(el, ".pref-highlight")).toHaveLength(0);
  });

  it("labels cases open or closed", async () => {
    const el = mount();
    getGuest360.emit(clone(fixture));
    await flush();
    expect(text(el)).toContain("New (open)");
    expect(text(el)).toContain("Closed (closed)");
  });

  it("shows do-not-contact warning and consent details", async () => {
    const el = mount();
    getGuest360.emit(clone(fixture));
    await flush();
    expect(text(el)).toContain("Do not contact");
    expect(text(el)).toContain("Opted in");
    expect(text(el)).toContain("Web form");
    expect(text(el)).toContain("Consent given");
  });

  it("hides do-not-contact warning when false and shows not-recorded marketing", async () => {
    const d = clone(fixture);
    d.consent.doNotContact = false;
    d.consent.marketingConsent = null;
    const el = mount();
    getGuest360.emit(d);
    await flush();
    expect(text(el)).not.toContain("Do not contact");
    expect(text(el)).toContain("Not recorded");
  });

  it("shows no-GDPR-form text when form date missing, hides section when form not accessible", async () => {
    const d = clone(fixture);
    d.consent.gdprFormDate = null;
    const el = mount();
    getGuest360.emit(d);
    await flush();
    expect(text(el)).toContain("No GDPR form on file.");

    const d2 = clone(fixture);
    d2.consent.formAccessible = false;
    const el2 = mount();
    getGuest360.emit(d2);
    await flush();
    expect(el2.shadowRoot.textContent).not.toContain("Latest GDPR form");
  });
});
