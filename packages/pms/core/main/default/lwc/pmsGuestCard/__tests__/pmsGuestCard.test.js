import { createElement } from "lwc";
import PmsGuestCard from "c/pmsGuestCard";
import getGuestCard from "@salesforce/apex/PMS_Guest360Controller.getGuestCard";
import { getRecord } from "lightning/uiRecordApi";

jest.mock(
  "@salesforce/apex/PMS_Guest360Controller.getGuestCard",
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

const CONTACT = "003000000000001AAA";
const BOOKING = "a00000000000001AAA";
// Wait a full macrotask: the card resets state in renderedCallback, so one microtask is not always enough.
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((r) => setTimeout(r, 0));
const q = (el, sel) => el.shadowRoot.querySelector(sel);
const text = (el) => el.shadowRoot.textContent.replace(/\s+/g, " ");

const card = (over = {}) => ({
  contactId: CONTACT,
  name: "Ada Lovelace",
  vipLevel: "Gold",
  idVerified: true,
  dietary: "Vegetarian",
  accessibilityNeeds: "Step-free room",
  balanceAccessible: true,
  balanceDue: 42.5,
  topPreferences: [
    { preferenceId: "p1", category: "Room", value: "High floor" },
    { preferenceId: "p2", category: "Food", value: "No nuts" },
    { preferenceId: "p3", value: "Late checkout" },
    { preferenceId: "p4", category: "Extra", value: "Fourth pref" }
  ],
  ...over
});

function mount(props = {}) {
  const el = createElement("c-pms-guest-card", { is: PmsGuestCard });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}

describe("c-pms-guest-card", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders nothing without a contact", async () => {
    const el = mount();
    await flush();
    expect(q(el, "lightning-card")).toBeNull();
    expect(el.shadowRoot.children).toHaveLength(0);
  });

  it("shows a spinner until data arrives", async () => {
    const el = mount({ contactId: CONTACT });
    await flush();
    expect(q(el, "lightning-spinner")).not.toBeNull();
    expect(q(el, "a")).toBeNull();
  });

  it("renders name, VIP, ID, dietary, accessibility and top 3 prefs", async () => {
    const el = mount({ contactId: CONTACT });
    getGuestCard.emit(card());
    await flush();
    expect(q(el, "lightning-spinner")).toBeNull();
    const t = text(el);
    expect(t).toContain("Ada Lovelace");
    expect(t).toContain("VIP: Gold");
    expect(t).toContain("ID verified");
    expect(t).toContain("Vegetarian");
    expect(t).toContain("Step-free room");
    const items = [...el.shadowRoot.querySelectorAll("li")].map(
      (li) => li.textContent
    );
    expect(items).toEqual([
      "Room: High floor",
      "Food: No nuts",
      "Late checkout"
    ]);
    expect(t).not.toContain("Fourth pref");
    const num = q(el, "lightning-formatted-number");
    expect(num.value).toBe(42.5);
    expect(num.formatStyle).toBe("currency");
    expect(num.currencyCode).toBe("USD");
  });

  it("omits optional sections and shows ID not verified", async () => {
    const el = mount({ contactId: CONTACT });
    getGuestCard.emit(
      card({
        vipLevel: null,
        idVerified: false,
        dietary: null,
        accessibilityNeeds: null,
        topPreferences: []
      })
    );
    await flush();
    const t = text(el);
    expect(t).not.toContain("VIP:");
    expect(t).toContain("ID not verified");
    expect(t).not.toContain("Dietary:");
    expect(t).not.toContain("Accessibility:");
    expect(el.shadowRoot.querySelectorAll("li")).toHaveLength(0);
  });

  it("hides balance when balanceAccessible is false", async () => {
    const el = mount({ contactId: CONTACT });
    getGuestCard.emit(card({ balanceAccessible: false }));
    await flush();
    expect(q(el, "lightning-formatted-number")).toBeNull();
    expect(text(el)).not.toContain("Balance due");
  });

  it("resolves the contact from a booking page via getRecord", async () => {
    const el = mount({
      recordId: BOOKING,
      objectApiName: "PMS_Booking__c"
    });
    await flush();
    expect(q(el, "lightning-card")).toBeNull();
    getRecord.emit({
      id: BOOKING,
      fields: {
        Primary_Contact__c: { value: CONTACT, displayValue: null }
      }
    });
    await flush();
    expect(q(el, "lightning-card")).not.toBeNull();
    expect(getGuestCard.getLastConfig()).toEqual({ contactId: CONTACT });
    getGuestCard.emit(card());
    await flush();
    expect(text(el)).toContain("Ada Lovelace");
  });

  it("navigates to the Contact from Open Guest 360", async () => {
    const el = mount({ contactId: CONTACT });
    getGuestCard.emit(card());
    await flush();
    q(el, "a").click();
    expect(mockNavigate).toHaveBeenCalledTimes(1);
    expect(mockNavigate.mock.calls[0][0]).toEqual({
      type: "standard__recordPage",
      attributes: {
        recordId: CONTACT,
        objectApiName: "Contact",
        actionName: "view"
      }
    });
  });

  it("shows an error alert when the wire fails", async () => {
    const el = mount({ contactId: CONTACT });
    getGuestCard.error({ message: "No access" }, 403);
    await flush();
    const alert = q(el, "[role=alert]");
    expect(alert).not.toBeNull();
    expect(alert.textContent).toContain("No access");
    expect(q(el, "lightning-spinner")).toBeNull();
    expect(q(el, "a")).toBeNull();
  });

  it("resets state when the contact changes", async () => {
    const OTHER = "003000000000002AAA";
    const el = mount({ contactId: CONTACT });
    getGuestCard.emit(card());
    await flush();
    expect(text(el)).toContain("Ada Lovelace");
    el.contactId = OTHER;
    await flush();
    await flush();
    expect(text(el)).not.toContain("Ada Lovelace");
    expect(q(el, "lightning-spinner")).not.toBeNull();
    getGuestCard.emit(card({ contactId: OTHER, name: "Grace Hopper" }));
    await flush();
    expect(text(el)).toContain("Grace Hopper");
    expect(q(el, "lightning-spinner")).toBeNull();
  });
});
