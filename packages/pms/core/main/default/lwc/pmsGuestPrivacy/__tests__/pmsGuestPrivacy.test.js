import { createElement } from "lwc";
import PmsGuestPrivacy from "c/pmsGuestPrivacy";
import exportGuestData from "@salesforce/apex/PMS_GuestPrivacyController.exportGuestData";
import anonymiseGuest from "@salesforce/apex/PMS_GuestPrivacyController.anonymiseGuest";

jest.mock(
  "@salesforce/apex/PMS_GuestPrivacyController.exportGuestData",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PMS_GuestPrivacyController.anonymiseGuest",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/PMS_Guest_Privacy",
  () => ({ default: true }),
  { virtual: true }
);

const CONTACT = "003000000000001AAA";
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((r) => setTimeout(r, 0));
const q = (el, sel) => el.shadowRoot.querySelector(sel);
const btn = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

function mount() {
  const el = createElement("c-pms-guest-privacy", { is: PmsGuestPrivacy });
  el.recordId = CONTACT;
  document.body.appendChild(el);
  return el;
}

async function openModal(el) {
  btn(el, "Anonymise guest").click();
  await flush();
}

async function fill(el, reason, confirm) {
  // handlers read event.target.value
  const ta = q(el, "lightning-textarea");
  ta.value = reason;
  ta.dispatchEvent(new CustomEvent("change"));
  const inp = q(el, "lightning-input");
  inp.value = confirm;
  inp.dispatchEvent(new CustomEvent("change"));
  await flush();
}

describe("c-pms-guest-privacy", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    global.URL.createObjectURL = jest.fn(() => "blob:x");
    global.URL.revokeObjectURL = jest.fn();
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders the card for a user with the permission", () => {
    const el = mount();
    expect(q(el, "lightning-card")).not.toBeNull();
    expect(btn(el, "Export guest data")).toBeTruthy();
  });

  it("is hidden without the custom permission", async () => {
    jest.resetModules();
    jest.doMock(
      "@salesforce/customPermission/PMS_Guest_Privacy",
      () => ({ default: false }),
      { virtual: true }
    );
    const { createElement: ce } = require("lwc");
    const Cmp = require("c/pmsGuestPrivacy").default;
    const el = ce("c-pms-guest-privacy-denied", { is: Cmp });
    document.body.appendChild(el);
    await flush();
    expect(el.shadowRoot.querySelector("lightning-card")).toBeNull();
    expect(el.shadowRoot.querySelectorAll("lightning-button").length).toBe(0);
    jest.dontMock("@salesforce/customPermission/PMS_Guest_Privacy");
  });

  it("export calls Apex and triggers a JSON download", async () => {
    exportGuestData.mockResolvedValue('{"contactId":"x"}');
    const click = jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});
    const el = mount();
    btn(el, "Export guest data").click();
    await flush();
    expect(exportGuestData).toHaveBeenCalledWith({ contactId: CONTACT });
    expect(global.URL.createObjectURL).toHaveBeenCalledTimes(1);
    const blob = global.URL.createObjectURL.mock.calls[0][0];
    expect(blob.type).toBe("application/json");
    expect(click).toHaveBeenCalledTimes(1);
    expect(q(el, "[role=status]").textContent).toBe("Guest data exported.");
    click.mockRestore();
  });

  it("shows an error when export fails and does not download", async () => {
    exportGuestData.mockRejectedValue({
      body: { message: "Export failed: x" }
    });
    const el = mount();
    btn(el, "Export guest data").click();
    await flush();
    expect(q(el, "[role=alert]").textContent).toBe("Export failed: x");
    expect(global.URL.createObjectURL).not.toHaveBeenCalled();
  });

  it("anonymise button opens the modal with confirm disabled", async () => {
    const el = mount();
    expect(q(el, "section[role=dialog]")).toBeNull();
    await openModal(el);
    expect(q(el, "section[role=dialog]")).not.toBeNull();
    expect(btn(el, "Anonymise").disabled).toBe(true);
  });

  it("requires a reason and the confirmation word", async () => {
    const el = mount();
    await openModal(el);
    await fill(el, "", "ANONYMISE");
    expect(btn(el, "Anonymise").disabled).toBe(true);
    await fill(el, "Erasure request", "nope");
    expect(btn(el, "Anonymise").disabled).toBe(true);
    await fill(el, "   ", "ANONYMISE");
    expect(btn(el, "Anonymise").disabled).toBe(true);
    await fill(el, "Erasure request", "anonymise");
    expect(btn(el, "Anonymise").disabled).toBe(false);
    expect(anonymiseGuest).not.toHaveBeenCalled();
  });

  it("shows the block reason and keeps the modal open when blocked", async () => {
    anonymiseGuest.mockResolvedValue({
      success: false,
      blocked: true,
      message: "The guest has an unpaid booking balance."
    });
    const el = mount();
    await openModal(el);
    await fill(el, "Erasure request", "ANONYMISE");
    btn(el, "Anonymise").click();
    await flush();
    expect(anonymiseGuest).toHaveBeenCalledWith({
      contactId: CONTACT,
      reason: "Erasure request"
    });
    expect(q(el, "section[role=dialog]")).not.toBeNull();
    expect(q(el, "[role=alert]").textContent).toContain(
      "The guest has an unpaid booking balance."
    );
  });

  it("shows a thrown Apex error in the modal", async () => {
    anonymiseGuest.mockRejectedValue({ body: { message: "No permission" } });
    const el = mount();
    await openModal(el);
    await fill(el, "Erasure request", "ANONYMISE");
    btn(el, "Anonymise").click();
    await flush();
    expect(q(el, "[role=alert]").textContent).toContain("No permission");
  });

  it("closes the modal and shows the success notice on success", async () => {
    anonymiseGuest.mockResolvedValue({
      success: true,
      message: "Guest anonymised."
    });
    const el = mount();
    await openModal(el);
    await fill(el, "Erasure request", "ANONYMISE");
    btn(el, "Anonymise").click();
    await flush();
    expect(q(el, "section[role=dialog]")).toBeNull();
    expect(q(el, "[role=status]").textContent).toBe("Guest anonymised.");
  });

  it("cancel closes the modal without calling Apex", async () => {
    const el = mount();
    await openModal(el);
    btn(el, "Cancel").click();
    await flush();
    expect(q(el, "section[role=dialog]")).toBeNull();
    expect(anonymiseGuest).not.toHaveBeenCalled();
  });
});
