import { createElement } from "lwc";
import PmsFrontDeskToday from "c/pmsFrontDeskToday";
import getSites from "@salesforce/apex/PMS_UIController.getSites";
import getFrontDesk from "@salesforce/apex/PMS_UIController.getFrontDesk";

jest.mock(
  "@salesforce/apex/PMS_UIController.getSites",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PMS_UIController.getFrontDesk",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PMS_UIController.checkIn",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PMS_UIController.checkOut",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PMS_Guest360Controller.getGuestCard",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((r) => setTimeout(r, 0));
const q = (el, sel) => el.shadowRoot.querySelector(sel);
const qa = (el, sel) => [...el.shadowRoot.querySelectorAll(sel)];

const desk = (arrivals) => ({
  arrivals,
  inHouse: [],
  departures: [],
  freeRooms: [],
  totalRooms: 2,
  dirtyRooms: 0
});
const arrival = (id, contactId, guest = "Ada") => ({
  id,
  guest,
  name: "B-" + id,
  roomType: "Double",
  startDate: "2026-11-24",
  endDate: "2026-11-25",
  adults: 2,
  contactId
});

async function mount(arrivals) {
  getFrontDesk.mockResolvedValue(desk(arrivals));
  const el = createElement("c-pms-front-desk-today", {
    is: PmsFrontDeskToday
  });
  document.body.appendChild(el);
  getSites.emit([{ label: "Hotel", value: "a01000000000001AAA" }]);
  await flush();
  await flush();
  return el;
}
const guestButtons = (el) =>
  qa(el, "lightning-button").filter(
    (b) => b.dataset.id && b.label !== "Check in"
  );

describe("c-pms-front-desk-today guest card", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a Guest button only for arrivals with a contact", async () => {
    const el = await mount([
      arrival("b1", "003000000000001AAA"),
      arrival("b2", null, "NoContact")
    ]);
    const buttons = guestButtons(el);
    expect(buttons).toHaveLength(1);
    expect(buttons[0].dataset.id).toBe("b1");
    expect(buttons[0].label).toBe("Guest");
  });

  it("toggles the inline card and the aria state", async () => {
    const el = await mount([arrival("b1", "003000000000001AAA")]);
    let btn = guestButtons(el)[0];
    expect(btn.getAttribute("aria-expanded")).toBe("false");
    expect(btn.title).toBe("Show guest card for Ada");
    expect(q(el, "c-pms-guest-card")).toBeNull();

    btn.click();
    await flush();
    btn = guestButtons(el)[0];
    expect(btn.label).toBe("Hide guest");
    expect(btn.getAttribute("aria-expanded")).toBe("true");
    expect(btn.title).toBe("Hide guest card for Ada");
    const card = q(el, "c-pms-guest-card");
    expect(card).not.toBeNull();
    expect(card.contactId).toBe("003000000000001AAA");

    btn.click();
    await flush();
    btn = guestButtons(el)[0];
    expect(btn.label).toBe("Guest");
    expect(btn.getAttribute("aria-expanded")).toBe("false");
    expect(q(el, "c-pms-guest-card")).toBeNull();
  });

  it("opens cards independently per arrival", async () => {
    const el = await mount([
      arrival("b1", "003000000000001AAA"),
      arrival("b2", "003000000000002AAA", "Grace")
    ]);
    guestButtons(el)[1].click();
    await flush();
    const cards = qa(el, "c-pms-guest-card");
    expect(cards).toHaveLength(1);
    expect(cards[0].contactId).toBe("003000000000002AAA");
  });
});
