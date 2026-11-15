import { LightningElement } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import PDF_LIB from "@salesforce/resourceUrl/pmsPdfLib";
import getHome from "@salesforce/apex/PMS_PortalV2Controller.getHome";
import getDocument from "@salesforce/apex/PMS_PortalV2Controller.getDocument";
import getSignedDocument from "@salesforce/apex/PMS_PortalV2Controller.getSignedDocument";
import signDocument from "@salesforce/apex/PMS_PortalV2Controller.signDocument";
import attachSignedPdf from "@salesforce/apex/PMS_PortalV2Controller.attachSignedPdf";
import declineDocument from "@salesforce/apex/PMS_PortalV2Controller.declineDocument";
import submitCheckIn from "@salesforce/apex/PMS_PortalV2Controller.submitCheckIn";
import acceptMilestone from "@salesforce/apex/PMS_PortalV2Controller.acceptMilestone";
import queryMilestone from "@salesforce/apex/PMS_PortalV2Controller.queryMilestone";
import decideApproval from "@salesforce/apex/PMS_PortalV2Controller.decideApproval";

const BADGE = {
  Sent: "badge badge-new",
  Viewed: "badge badge-new",
  Signed: "badge badge-done",
  Declined: "badge badge-bad",
  Pending: "badge badge-new",
  Approved: "badge badge-done",
  Rejected: "badge badge-bad",
  Completed: "badge badge-wait",
  Accepted: "badge badge-done",
  "In Progress": "badge badge-active",
  "Not Started": "badge badge-muted",
  Missed: "badge badge-bad"
};

function errorText(e) {
  if (!e) return "Something went wrong.";
  if (e.body && e.body.message) return e.body.message;
  return e.message || String(e);
}
function day(v) {
  if (!v) return "";
  const d = new Date(String(v).length === 10 ? v + "T12:00:00" : v);
  return d.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric"
  });
}
function money(v) {
  return v === null || v === undefined
    ? ""
    : new Intl.NumberFormat("sv-SE", { maximumFractionDigits: 2 }).format(v);
}
function toBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
/** The standard PDF fonts only cover Latin-1. */
function latin1(s) {
  return String(s || "")
    .replace(/[\u2013\u2014\u2212]/g, "-")
    .replace(/[\u2018\u2019\u201A]/g, "'")
    .replace(/[\u201C\u201D\u201E]/g, '"')
    .replace(/\u2026/g, "...")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[^\x20-\x7E\xA0-\xFF]/g, "");
}

export default class PmsCustomerPortalV2 extends LightningElement {
  home;
  loading = true;
  busy = false;
  error;
  notice;
  // documents
  signingId;
  signerName = "";
  consent = false;
  hasInk = false;
  decliningId;
  declineReason = "";
  // check-in
  openCheckInId;
  checkInError;
  // projects
  commentFor = {};

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.home = await getHome();
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.loading = false;
    }
  }

  // ------------------------------------------------------------------ view models

  get ready() {
    return !this.loading && this.home;
  }
  get greeting() {
    return (
      "Hello" +
      (this.home && this.home.firstName ? ", " + this.home.firstName : "")
    );
  }
  get actionsLabel() {
    const n = this.home ? this.home.actionCount : 0;
    return n === 0
      ? "Nothing needs your attention right now."
      : n === 1
        ? "1 thing needs your attention."
        : n + " things need your attention.";
  }
  get documents() {
    return (this.home ? this.home.documents : []).map((d) => ({
      ...d,
      badge: BADGE[d.status] || "badge",
      dueLabel: d.dueDate ? "Please respond by " + day(d.dueDate) : "",
      signedLabel: d.signedAt
        ? "Signed by " + d.signerName + " on " + day(d.signedAt)
        : "",
      signing: this.signingId === d.id,
      declining: this.decliningId === d.id,
      idle: this.signingId !== d.id && this.decliningId !== d.id,
      canDecline: d.canSign
    }));
  }
  get hasDocuments() {
    return this.documents.length > 0;
  }
  get checkIns() {
    return (this.home ? this.home.checkIns : []).map((c) => ({
      ...c,
      open: this.openCheckInId === c.bookingId && !c.done,
      kindLabel:
        c.kind === "clinic"
          ? "Health questionnaire"
          : c.kind === "movein"
            ? "Move-in details"
            : "Online check-in",
      badge: c.done ? "badge badge-done" : "badge badge-new",
      statusLabel: c.done ? "Done" : "To do"
    }));
  }
  get hasCheckIns() {
    return this.checkIns.length > 0;
  }
  get projects() {
    return (this.home ? this.home.projects : []).map((p) => ({
      ...p,
      progress:
        p.percentComplete === null || p.percentComplete === undefined
          ? 0
          : Math.round(p.percentComplete),
      progressStyle: "width:" + (p.percentComplete || 0) + "%",
      dates: day(p.startDate) + " – " + day(p.endDate),
      hasApprovals: p.approvals.length > 0,
      milestones: p.milestones.map((m) => ({
        ...m,
        badge: BADGE[m.status] || "badge",
        dueLabel: day(m.dueDate),
        amountLabel: money(m.amount),
        acceptedLabel: m.acceptedAt ? "Accepted " + day(m.acceptedAt) : ""
      })),
      approvals: p.approvals.map((a) => ({
        ...a,
        badge: BADGE[a.status] || "badge",
        amountLabel:
          a.amount !== null && a.amount !== undefined
            ? "Cost impact: " + money(a.amount)
            : "",
        scheduleLabel: a.scheduleDays
          ? "Schedule impact: " + a.scheduleDays + " days"
          : "",
        dueLabel: a.dueDate ? "Decide by " + day(a.dueDate) : "",
        decidedLabel: a.decidedAt ? a.status + " " + day(a.decidedAt) : ""
      }))
    }));
  }
  get hasProjects() {
    return this.projects.length > 0;
  }
  get signDisabled() {
    return (
      this.busy ||
      !this.consent ||
      !this.hasInk ||
      this.signerName.trim().length < 3
    );
  }

  // ------------------------------------------------------------------ documents

  async openDocument(event) {
    const id = event.currentTarget.dataset.id;
    await this.download(() => getDocument({ requestId: id }), true);
    this.patchDoc(id, { status: "Viewed" }, (d) => d.status === "Sent"); // the server does the same on first open
  }

  async openSigned(event) {
    const id = event.currentTarget.dataset.id;
    await this.download(() => getSignedDocument({ requestId: id }), false);
  }

  async download(fetcher, inline) {
    this.busy = true;
    this.error = undefined;
    try {
      const f = await fetcher();
      const type =
        f.extension === "pdf" ? "application/pdf" : "application/octet-stream";
      const url = URL.createObjectURL(new Blob([toBytes(f.base64)], { type }));
      const a = document.createElement("a");
      a.href = url;
      if (inline && f.extension === "pdf") {
        a.target = "_blank";
        a.rel = "noopener";
      } else {
        a.download = f.fileName;
      }
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.busy = false;
    }
  }

  patchDoc(id, changes, when) {
    if (!this.home) return;
    this.home = {
      ...this.home,
      documents: this.home.documents.map((d) => {
        return d.id === id && (!when || when(d)) ? { ...d, ...changes } : d;
      })
    };
  }

  startSigning(event) {
    this.signingId = event.currentTarget.dataset.id;
    this.decliningId = undefined;
    this.signerName = "";
    this.consent = false;
    this.hasInk = false;
    this.error = undefined;
    // the canvas is rendered on the next cycle
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => this.setupCanvas(), 0);
  }

  cancelSigning() {
    this.signingId = undefined;
  }

  handleSignerName(event) {
    this.signerName = event.detail.value || "";
  }

  handleConsent(event) {
    this.consent = event.target.checked;
  }

  setupCanvas() {
    const canvas = this.template.querySelector("canvas.pad");
    if (!canvas) return;
    const ratio = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * ratio;
    canvas.height = rect.height * ratio;
    const ctx = canvas.getContext("2d");
    ctx.scale(ratio, ratio);
    ctx.lineWidth = 2.2;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.strokeStyle = "#102a43";
    let drawing = false;
    const pos = (e) => {
      const r = canvas.getBoundingClientRect();
      return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    canvas.onpointerdown = (e) => {
      drawing = true;
      canvas.setPointerCapture(e.pointerId);
      const p = pos(e);
      ctx.beginPath();
      ctx.moveTo(p.x, p.y);
    };
    canvas.onpointermove = (e) => {
      if (!drawing) return;
      const p = pos(e);
      ctx.lineTo(p.x, p.y);
      ctx.stroke();
      this.hasInk = true;
    };
    canvas.onpointerup = () => {
      drawing = false;
    };
    canvas.onpointerleave = () => {
      drawing = false;
    };
  }

  clearPad() {
    const canvas = this.template.querySelector("canvas.pad");
    if (canvas) {
      canvas.getContext("2d").clearRect(0, 0, canvas.width, canvas.height);
    }
    this.hasInk = false;
  }

  async sign() {
    const canvas = this.template.querySelector("canvas.pad");
    const id = this.signingId;
    this.busy = true;
    this.error = undefined;
    try {
      const signaturePng = canvas.toDataURL("image/png");
      const result = await signDocument({
        requestId: id,
        signerName: this.signerName,
        signaturePng,
        userAgent: navigator.userAgent,
        consent: this.consent
      });
      this.patchDoc(id, {
        status: "Signed",
        canSign: false,
        signerName: result.signerName,
        signedAt: new Date().toISOString()
      });
      this.signingId = undefined;
      this.notice = "Thank you, the document is signed.";
      await this.fileSignedCopy(id, result, signaturePng);
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.busy = false;
    }
  }

  /** Stamps a signed copy of the PDF in the browser and files it. The signature itself is already recorded. */
  async fileSignedCopy(id, s, signaturePng) {
    try {
      await loadScript(this, PDF_LIB);
      const { PDFDocument, StandardFonts, rgb } = window.PDFLib;
      const original = await getDocument({ requestId: id });
      if (original.extension !== "pdf") return;
      const doc = await PDFDocument.load(toBytes(original.base64), {
        ignoreEncryption: true
      });
      const font = await doc.embedFont(StandardFonts.Helvetica);
      const bold = await doc.embedFont(StandardFonts.HelveticaBold);
      const footer = latin1(
        "Signed electronically by " +
          s.signerName +
          " on " +
          s.signedAtLabel +
          " - " +
          s.requestName
      );
      const pages = doc.getPages();
      pages.forEach((p, i) => {
        p.drawText(
          footer + " - page " + (i + 1) + " of " + (pages.length + 1),
          { x: 36, y: 16, size: 7, font, color: rgb(0.35, 0.35, 0.35) }
        );
      });
      const page = doc.addPage([595.28, 841.89]);
      let y = 780;
      const line = (label, value, size = 10) => {
        page.drawText(latin1(label), {
          x: 56,
          y,
          size: 9,
          font,
          color: rgb(0.4, 0.4, 0.4)
        });
        page.drawText(latin1(value), {
          x: 190,
          y,
          size,
          font: bold,
          color: rgb(0.1, 0.1, 0.1)
        });
        y -= 22;
      };
      page.drawText("Signature page", { x: 56, y, size: 20, font: bold });
      y -= 40;
      line("Document", s.title);
      line("Reference", s.requestName);
      line("Signed by", s.signerName);
      line("Email", s.signerEmail || "");
      line("Signed at", s.signedAtLabel);
      line("IP address", s.ip || "not available");
      page.drawText("SHA-256 of the signed document", {
        x: 56,
        y,
        size: 9,
        font,
        color: rgb(0.4, 0.4, 0.4)
      });
      page.drawText(s.documentHash.slice(0, 32), { x: 190, y, size: 8, font });
      page.drawText(s.documentHash.slice(32), {
        x: 190,
        y: y - 11,
        size: 8,
        font
      });
      y -= 50;
      page.drawText("Signature", {
        x: 56,
        y,
        size: 9,
        font,
        color: rgb(0.4, 0.4, 0.4)
      });
      const img = await doc.embedPng(toBytes(signaturePng.split(",")[1]));
      const scale = Math.min(260 / img.width, 110 / img.height, 1);
      page.drawImage(img, {
        x: 190,
        y: y - img.height * scale + 10,
        width: img.width * scale,
        height: img.height * scale
      });
      y -= 140;
      const statement = latin1(
        "The person named above signed this document electronically in the " +
          (s.companyName || "") +
          " customer portal after logging in, confirming that the typed name and drawn signature are their electronic signature."
      );
      const words = statement.split(" ");
      let row = "";
      words.forEach((w) => {
        if (font.widthOfTextAtSize(row + w + " ", 9) > 480) {
          page.drawText(row, { x: 56, y, size: 9, font });
          y -= 13;
          row = "";
        }
        row += w + " ";
      });
      page.drawText(row, { x: 56, y, size: 9, font });
      const out = await doc.saveAsBase64();
      const row2 = await attachSignedPdf({ requestId: id, base64Data: out });
      if (row2) this.patchDoc(id, row2);
      this.notice =
        "Thank you, the document is signed. A signed copy is ready to download.";
    } catch {
      // the signature is recorded; staff can prepare the copy
      this.notice =
        "Thank you, the document is signed. We will add the signed copy shortly.";
    }
  }

  startDecline(event) {
    this.decliningId = event.currentTarget.dataset.id;
    this.signingId = undefined;
    this.declineReason = "";
  }

  cancelDecline() {
    this.decliningId = undefined;
  }

  handleDeclineReason(event) {
    this.declineReason = event.detail.value;
  }

  async sendDecline() {
    const id = this.decliningId;
    this.busy = true;
    this.error = undefined;
    try {
      await declineDocument({ requestId: id, reason: this.declineReason });
      this.patchDoc(id, { status: "Declined", canSign: false });
      this.decliningId = undefined;
      this.notice = "Thanks, we have let the team know.";
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.busy = false;
    }
  }

  // ------------------------------------------------------------------ check-in

  toggleCheckIn(event) {
    const id = event.currentTarget.dataset.id;
    this.openCheckInId = this.openCheckInId === id ? undefined : id;
    this.checkInError = undefined;
  }

  async handleCheckIn(event) {
    this.busy = true;
    this.checkInError = undefined;
    try {
      const list = await submitCheckIn({
        bookingId: event.detail.bookingId,
        formJson: event.detail.formJson
      });
      this.home = {
        ...this.home,
        checkIns: list,
        actionCount: Math.max(0, this.home.actionCount - 1)
      };
      this.openCheckInId = undefined;
      this.notice = "Thank you! We have your details.";
    } catch (e) {
      this.checkInError = errorText(e);
    } finally {
      this.busy = false;
    }
  }

  // ------------------------------------------------------------------ projects

  handleComment(event) {
    this.commentFor = {
      ...this.commentFor,
      [event.target.dataset.id]: event.detail.value
    };
  }

  async projectAction(call, okMessage) {
    this.busy = true;
    this.error = undefined;
    try {
      const projects = await call();
      const pending = projects.reduce(
        (n, p) =>
          n +
          p.milestones.filter((m) => m.canAccept).length +
          p.approvals.filter((a) => a.canDecide).length,
        0
      );
      const before = this.home.projects.reduce(
        (n, p) =>
          n +
          p.milestones.filter((m) => m.canAccept).length +
          p.approvals.filter((a) => a.canDecide).length,
        0
      );
      this.home = {
        ...this.home,
        projects,
        actionCount: Math.max(0, this.home.actionCount - (before - pending))
      };
      this.notice = okMessage;
    } catch (e) {
      this.error = errorText(e);
    } finally {
      this.busy = false;
    }
  }

  accept(event) {
    const id = event.currentTarget.dataset.id;
    this.projectAction(
      () => acceptMilestone({ milestoneId: id, comment: this.commentFor[id] }),
      "Milestone accepted. Thank you!"
    );
  }

  query(event) {
    const id = event.currentTarget.dataset.id;
    this.projectAction(
      () => queryMilestone({ milestoneId: id, comment: this.commentFor[id] }),
      "Thanks, the project team will get back to you."
    );
  }

  approve(event) {
    const id = event.currentTarget.dataset.id;
    this.projectAction(
      () =>
        decideApproval({
          requestId: id,
          approve: true,
          comment: this.commentFor[id]
        }),
      "Approved. Thank you!"
    );
  }

  reject(event) {
    const id = event.currentTarget.dataset.id;
    this.projectAction(
      () =>
        decideApproval({
          requestId: id,
          approve: false,
          comment: this.commentFor[id]
        }),
      "Rejected. The team has been told."
    );
  }

  dismissNotice() {
    this.notice = undefined;
  }
}
