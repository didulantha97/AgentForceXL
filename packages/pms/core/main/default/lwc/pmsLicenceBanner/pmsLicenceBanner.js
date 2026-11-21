import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getStatus from "@salesforce/apex/PMS_LicenceController.getStatus";
import saveLicenceKey from "@salesforce/apex/PMS_LicenceController.saveLicenceKey";

export default class PmsLicenceBanner extends LightningElement {
  status;
  loadError;
  keyText = "";
  saving = false;
  saveError;
  showForm = false;
  _wired;

  @wire(getStatus)
  wiredStatus(result) {
    this._wired = result;
    if (result.data) {
      this.status = result.data;
      this.loadError = undefined;
    } else if (result.error) {
      this.loadError = this.reduceError(result.error);
    }
  }

  get state() {
    return this.status ? this.status.state : undefined;
  }

  get hasBanner() {
    return !!(this.status && this.status.bannerText);
  }

  get bannerClass() {
    const tone = this.state === "SUSPENDED" ? "error" : "warning";
    return `slds-notify slds-notify_alert slds-alert_${tone}`;
  }

  get bannerIcon() {
    return this.state === "SUSPENDED" ? "utility:error" : "utility:warning";
  }

  get canManage() {
    return !!(this.status && this.status.canManage && this.state !== "DEV");
  }

  get cardTitle() {
    return "PMS licence";
  }

  get summary() {
    if (!this.status) {
      return "";
    }
    const s = this.status;
    const edition = s.edition ? `${s.edition} edition` : "";
    switch (s.state) {
      case "PILOT":
        return `Pilot access, ${s.daysRemaining} days left (until ${s.endDate}).`;
      case "ACTIVE":
        return `Licensed: ${edition}, valid until ${s.endDate}.`;
      case "GRACE":
        return `Licence expired, grace period ends ${s.endDate}.`;
      case "SUSPENDED":
        return "Account suspended: PMS is read-only. Enter a valid licence key to restore access.";
      default:
        return "";
    }
  }

  get formToggleLabel() {
    return this.showForm ? "Hide" : "Enter licence key";
  }

  get saveDisabled() {
    return this.saving || !this.keyText.trim();
  }

  toggleForm() {
    this.showForm = !this.showForm;
    this.saveError = undefined;
  }

  handleKeyChange(event) {
    this.keyText = event.target.value;
  }

  async handleSave() {
    this.saving = true;
    this.saveError = undefined;
    try {
      await saveLicenceKey({ token: this.keyText });
      this.keyText = "";
      this.showForm = false;
      await refreshApex(this._wired);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Licence key saved",
          message: "Your PMS licence key was validated and stored.",
          variant: "success"
        })
      );
    } catch (error) {
      this.saveError = this.reduceError(error);
    } finally {
      this.saving = false;
    }
  }

  reduceError(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return (error && error.message) || "Something went wrong.";
  }
}
