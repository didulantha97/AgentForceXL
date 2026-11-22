import { createElement } from "lwc";
import PmsDemoDataCard from "c/pmsDemoDataCard";
import getStatus from "@salesforce/apex/PMS_DemoDataController.getStatus";
import load from "@salesforce/apex/PMS_DemoDataController.load";
import reset from "@salesforce/apex/PMS_DemoDataController.reset";
const ShowToastEventName = "lightning__showtoast";

jest.mock(
  "@salesforce/apex/PMS_DemoDataController.getStatus",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/PMS_DemoDataController.load",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/PMS_DemoDataController.reset",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const pack = (key, state, records, extra = {}) => ({
  key,
  label: `Pack ${key}`,
  description: `About ${key}`,
  state,
  records,
  needsBaseline: key !== "baseline",
  ...extra
});

const status = (overrides = {}) => ({
  allowed: true,
  canRun: true,
  busy: false,
  total: 120,
  packs: [pack("baseline", "DONE", 120), pack("busy-weekend", "NONE", 0)],
  counts: [
    { label: "Bookings", count: 40 },
    { label: "Invoices", count: 30 }
  ],
  ...overrides
});

const flush = async () => {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

const buttons = (el, action) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].filter(
    (b) => b.dataset.action === action
  );

function mount(props = {}) {
  const el = createElement("c-pms-demo-data-card", { is: PmsDemoDataCard });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}

describe("c-pms-demo-data-card", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("renders nothing when the server says the user is not allowed", async () => {
    getStatus.mockResolvedValue({ allowed: false, packs: [], counts: [] });
    const el = mount();
    await flush();
    expect(el.shadowRoot.querySelector("lightning-card")).toBeNull();
  });

  it("shows the opt-in reason to an admin in a Developer Edition or trial org", async () => {
    getStatus.mockResolvedValue({
      allowed: false,
      optInRequired: true,
      reason: "Demo data is switched off until you opt in.",
      packs: [],
      counts: []
    });
    const el = mount();
    await flush();
    expect(el.shadowRoot.querySelector("lightning-card")).not.toBeNull();
    expect(el.shadowRoot.textContent).toContain("until you opt in");
  });

  it("renders nothing when the status call fails", async () => {
    getStatus.mockRejectedValue(new Error("boom"));
    const el = mount();
    await flush();
    expect(el.shadowRoot.querySelector("lightning-card")).toBeNull();
  });

  it("lists the packs with state, record counts and the totals", async () => {
    getStatus.mockResolvedValue(status());
    const el = mount({ cardTitle: "Demo" });
    await flush();
    const card = el.shadowRoot.querySelector("lightning-card");
    expect(card.title).toBe("Demo");
    expect(el.shadowRoot.querySelectorAll("li.slds-item")).toHaveLength(2);
    const badges = el.shadowRoot.querySelectorAll("lightning-badge");
    expect(badges[0].label).toBe("Loaded");
    expect(badges[1].label).toBe("Not loaded");
    expect(el.shadowRoot.textContent).toContain("120 records");
    expect(el.shadowRoot.textContent).toContain("Records created (120)");
    expect(el.shadowRoot.textContent).toContain("Bookings: 40");
  });

  it("only offers Load for packs that are not loaded, and Reset for those that are", async () => {
    getStatus.mockResolvedValue(status());
    const el = mount();
    await flush();
    const loads = buttons(el, "load");
    const resets = buttons(el, "reset");
    expect(loads[0].disabled).toBe(true); // baseline is loaded
    expect(loads[1].disabled).toBe(false);
    expect(resets[0].disabled).toBe(false);
    expect(resets[1].disabled).toBe(true); // nothing to remove
  });

  it("disables everything while a licence lock or a running job is in the way", async () => {
    getStatus.mockResolvedValue(
      status({ canRun: false, reason: "Your PMS licence is not active." })
    );
    const el = mount();
    await flush();
    expect(el.shadowRoot.textContent).toContain("licence is not active");
    expect(buttons(el, "load").every((b) => b.disabled)).toBe(true);
    expect(buttons(el, "reset").every((b) => b.disabled)).toBe(true);
  });

  it("loads a pack, shows a success toast and starts polling while busy", async () => {
    jest.useFakeTimers();
    getStatus.mockResolvedValue(status());
    const el = mount({ refreshSeconds: 3 });
    await flush();
    const toasts = [];
    el.addEventListener(ShowToastEventName, (e) => toasts.push(e.detail));
    load.mockResolvedValue(
      status({
        busy: true,
        message: 'Loading "busy-weekend" in the background (1 steps).',
        packs: [
          pack("baseline", "DONE", 120),
          pack("busy-weekend", "RUNNING", 0)
        ]
      })
    );
    buttons(el, "load")[1].click();
    await flush();
    expect(load).toHaveBeenCalledWith({ pack: "busy-weekend" });
    expect(toasts[0].variant).toBe("success");
    expect(el.shadowRoot.textContent).toContain("Loading");
    expect(el.shadowRoot.textContent).toContain("Working in the background");
    getStatus.mockClear();
    getStatus.mockResolvedValue(status({ busy: false }));
    jest.advanceTimersByTime(3000);
    await flush();
    expect(getStatus).toHaveBeenCalledTimes(1);
    // Polling stops once nothing is running any more
    jest.advanceTimersByTime(9000);
    await flush();
    expect(getStatus).toHaveBeenCalledTimes(1);
  });

  it("shows a warning when the server refuses", async () => {
    getStatus.mockResolvedValue(status());
    const el = mount();
    await flush();
    const toasts = [];
    el.addEventListener(ShowToastEventName, (e) => toasts.push(e.detail));
    load.mockResolvedValue(
      status({ message: "Refused: Demo data can only be loaded in a sandbox." })
    );
    buttons(el, "load")[1].click();
    await flush();
    expect(toasts[0].variant).toBe("warning");
    expect(toasts[0].message).toContain("Refused");
  });

  it("shows an error toast when the call throws", async () => {
    getStatus.mockResolvedValue(status());
    const el = mount();
    await flush();
    const toasts = [];
    el.addEventListener(ShowToastEventName, (e) => toasts.push(e.detail));
    load.mockRejectedValue({ body: { message: "No access" } });
    buttons(el, "load")[1].click();
    await flush();
    expect(toasts[0].variant).toBe("error");
    expect(toasts[0].message).toBe("No access");
  });

  it("asks for confirmation before resetting, and cancel backs out", async () => {
    getStatus.mockResolvedValue(status());
    const el = mount();
    await flush();
    buttons(el, "reset")[0].click();
    await flush();
    expect(buttons(el, "confirm")).toHaveLength(1);
    expect(reset).not.toHaveBeenCalled();
    const cancel = [...el.shadowRoot.querySelectorAll("lightning-button")].find(
      (b) => b.label === "Cancel"
    );
    cancel.click();
    await flush();
    expect(buttons(el, "confirm")).toHaveLength(0);
    expect(reset).not.toHaveBeenCalled();
  });

  it("resets a pack after the confirmation", async () => {
    getStatus.mockResolvedValue(status());
    const el = mount();
    await flush();
    reset.mockResolvedValue(
      status({
        message: "Removing 120 demo records in the background.",
        busy: true
      })
    );
    buttons(el, "reset")[0].click();
    await flush();
    buttons(el, "confirm")[0].click();
    await flush();
    expect(reset).toHaveBeenCalledWith({ pack: "baseline" });
    expect(el.shadowRoot.textContent).toContain("Removing 120 demo records");
    expect(buttons(el, "confirm")).toHaveLength(0);
  });

  it("shows why a pack failed", async () => {
    getStatus.mockResolvedValue(
      status({
        packs: [
          pack("baseline", "FAILED", 40, {
            message: "Step hotel failed: Room cap reached"
          })
        ]
      })
    );
    const el = mount();
    await flush();
    expect(el.shadowRoot.querySelector("lightning-badge").label).toBe("Failed");
    expect(el.shadowRoot.textContent).toContain("Room cap reached");
  });

  it("stops polling when removed from the page", async () => {
    jest.useFakeTimers();
    getStatus.mockResolvedValue(status({ busy: true }));
    const el = mount();
    await flush();
    document.body.removeChild(el);
    getStatus.mockClear();
    jest.advanceTimersByTime(20000);
    await flush();
    expect(getStatus).not.toHaveBeenCalled();
  });
});
