import { createElement } from "lwc";
import PmsLicenceBanner from "c/pmsLicenceBanner";
import getStatus from "@salesforce/apex/PMS_LicenceController.getStatus";
import saveLicenceKey from "@salesforce/apex/PMS_LicenceController.saveLicenceKey";
import { refreshApex } from "@salesforce/apex";

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/PMS_LicenceController.getStatus",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PMS_LicenceController.saveLicenceKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const saveButton = (el) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === "Save key"
  );
const flush = () => Promise.resolve();

function mount() {
  const el = createElement("c-pms-licence-banner", { is: PmsLicenceBanner });
  document.body.appendChild(el);
  return el;
}

describe("c-pms-licence-banner", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows an error-toned banner when suspended", async () => {
    const el = mount();
    getStatus.emit({
      state: "SUSPENDED",
      bannerText: "Suspended",
      canManage: true
    });
    await flush();
    const alert = el.shadowRoot.querySelector('[role="alert"]');
    expect(alert.textContent).toContain("Suspended");
    expect(alert.className).toContain("slds-alert_error");
  });

  it("shows a read-only summary when suspended", async () => {
    const el = mount();
    getStatus.emit({
      state: "SUSPENDED",
      bannerText: "Account suspended",
      canManage: true
    });
    await flush();
    expect(
      el.shadowRoot.querySelector("lightning-card p").textContent
    ).toContain("read-only");
  });

  it("shows a warning-toned banner for pilot and the summary", async () => {
    const el = mount();
    getStatus.emit({
      state: "PILOT",
      bannerText: "Pilot ends soon",
      daysRemaining: 5,
      endDate: "2026-12-01",
      canManage: true
    });
    await flush();
    expect(el.shadowRoot.querySelector('[role="alert"]').className).toContain(
      "slds-alert_warning"
    );
    expect(
      el.shadowRoot.querySelector("lightning-card p").textContent
    ).toContain("5 days left");
  });

  it("renders no banner and no card for DEV state or non-managers", async () => {
    const el = mount();
    getStatus.emit({ state: "DEV", canManage: true });
    await flush();
    expect(el.shadowRoot.querySelector('[role="alert"]')).toBeNull();
    expect(el.shadowRoot.querySelector("lightning-card")).toBeNull();
    getStatus.emit({
      state: "ACTIVE",
      edition: "Pro",
      endDate: "2027-01-01",
      canManage: false
    });
    await flush();
    expect(el.shadowRoot.querySelector("lightning-card")).toBeNull();
  });

  it("shows the load error", async () => {
    const el = mount();
    getStatus.error({ message: "boom" });
    await flush();
    expect(
      el.shadowRoot.querySelector(".slds-text-color_error").textContent
    ).toBe("boom");
  });

  it("saves a key, hides the form and clears the text", async () => {
    saveLicenceKey.mockResolvedValue();
    const el = mount();
    getStatus.emit({
      state: "ACTIVE",
      edition: "Pro",
      endDate: "2027-01-01",
      canManage: true
    });
    await flush();
    el.shadowRoot.querySelector('lightning-button[slot="actions"]').click();
    await flush();
    const ta = el.shadowRoot.querySelector("lightning-textarea");
    ta.value = "abc.def";
    ta.dispatchEvent(new CustomEvent("change"));
    await flush();
    saveButton(el).click();
    await flush();
    await flush();
    expect(saveLicenceKey).toHaveBeenCalledWith({ token: "abc.def" });
    expect(refreshApex).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.querySelector("lightning-textarea")).toBeNull();
  });

  it("keeps the form open and shows the error when save fails", async () => {
    saveLicenceKey.mockRejectedValue({ body: { message: "Invalid key" } });
    const el = mount();
    getStatus.emit({
      state: "ACTIVE",
      edition: "Pro",
      endDate: "2027-01-01",
      canManage: true
    });
    await flush();
    el.shadowRoot.querySelector('lightning-button[slot="actions"]').click();
    await flush();
    const ta = el.shadowRoot.querySelector("lightning-textarea");
    ta.value = "bad";
    ta.dispatchEvent(new CustomEvent("change"));
    await flush();
    saveButton(el).click();
    await flush();
    await flush();
    expect(refreshApex).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("lightning-textarea")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector(".slds-text-color_error").textContent
    ).toBe("Invalid key");
  });
});
