import { LightningElement, api } from "lwc";
import hasPrivacyPermission from "@salesforce/customPermission/PMS_Guest_Privacy";
import exportGuestData from "@salesforce/apex/PMS_GuestPrivacyController.exportGuestData";
import anonymiseGuest from "@salesforce/apex/PMS_GuestPrivacyController.anonymiseGuest";

/**
 * Right of access (JSON download) and right to erasure (anonymise) for a guest. Rendered only when the user has the
 * PMS_Guest_Privacy custom permission; the Apex methods enforce it again.
 */
export default class PmsGuestPrivacy extends LightningElement {
  @api recordId;

  busy = false;
  error;
  notice;
  showModal = false;
  reason = "";
  confirmText = "";
  blockMessage;

  get canManage() {
    return hasPrivacyPermission === true;
  }

  get confirmDisabled() {
    return (
      this.busy ||
      !this.reason.trim() ||
      this.confirmText.trim().toUpperCase() !== "ANONYMISE"
    );
  }

  static message(e) {
    return (
      (e && e.body && e.body.message) ||
      (e && e.message) ||
      "Something went wrong."
    );
  }

  async handleExport() {
    this.busy = true;
    this.error = undefined;
    this.notice = undefined;
    try {
      const json = await exportGuestData({ contactId: this.recordId });
      const blob = new Blob([json], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `guest-data-${this.recordId}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      this.notice = "Guest data exported.";
    } catch (e) {
      this.error = PmsGuestPrivacy.message(e);
    } finally {
      this.busy = false;
    }
  }

  openModal() {
    this.reason = "";
    this.confirmText = "";
    this.blockMessage = undefined;
    this.error = undefined;
    this.notice = undefined;
    this.showModal = true;
  }

  closeModal() {
    this.showModal = false;
  }

  handleReason(event) {
    this.reason = event.target.value || "";
  }

  handleConfirm(event) {
    this.confirmText = event.target.value || "";
  }

  async handleAnonymise() {
    this.busy = true;
    this.blockMessage = undefined;
    try {
      const res = await anonymiseGuest({
        contactId: this.recordId,
        reason: this.reason.trim()
      });
      if (res && res.success) {
        this.showModal = false;
        this.notice = res.message;
      } else {
        this.blockMessage = (res && res.message) || "Anonymisation failed.";
      }
    } catch (e) {
      this.blockMessage = PmsGuestPrivacy.message(e);
    } finally {
      this.busy = false;
    }
  }
}
