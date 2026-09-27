import { LightningElement, track } from "lwc";
import { getBiometricsService } from "lightning/mobileCapabilities";

const BIOMETRICS_OPTIONS = {
  permissionRequestTitle: "Verify Your Identity",
  permissionRequestBody:
    "Use biometrics to confirm you are the owner of this device.",
  additionalSupportedPolicies: ["PIN_CODE"]
};

const FAILURE_MESSAGES = {
  HARDWARE_NOT_AVAILABLE:
    "No fingerprint or face recognition hardware was found on this device.",
  NOT_CONFIGURED:
    "Biometrics hardware is present but not set up. Configure it in your device settings.",
  SERVICE_NOT_ENABLED: "The biometrics service is not enabled for this app."
};

export default class BiometricsComponent extends LightningElement {
  @track errorMessage = "";
  @track isVerifying = false;
  @track isReady = false;
  @track verificationResult = null; // null = not attempted, true = verified, false = rejected

  _biometrics = null;

  async connectedCallback() {
    this._biometrics = getBiometricsService();
    if (this.isAvailable) {
      try {
        this.isReady =
          await this._biometrics.isBiometricsReady(BIOMETRICS_OPTIONS);
      } catch (error) {
        this.errorMessage = this._formatError(error);
      }
    }
  }

  get isAvailable() {
    return this._biometrics != null && this._biometrics.isAvailable();
  }

  get isVerifyDisabled() {
    return this.isVerifying || !this.isReady;
  }

  get showNotReady() {
    return !this.isReady && !this.errorMessage;
  }

  get hasResult() {
    return this.verificationResult !== null;
  }

  get isVerified() {
    return this.verificationResult === true;
  }

  get isRejected() {
    return this.verificationResult === false;
  }

  async handleVerify() {
    this.errorMessage = "";
    this.verificationResult = null;
    this.isVerifying = true;

    try {
      this.verificationResult =
        await this._biometrics.checkUserIsDeviceOwner(BIOMETRICS_OPTIONS);
      this.dispatchEvent(
        new CustomEvent("verified", {
          detail: { isDeviceOwner: this.verificationResult }
        })
      );
    } catch (error) {
      this.errorMessage = this._formatError(error);
    } finally {
      this.isVerifying = false;
    }
  }

  handleReset() {
    this.verificationResult = null;
    this.errorMessage = "";
  }

  _formatError(error) {
    if (error && FAILURE_MESSAGES[error.code]) {
      return FAILURE_MESSAGES[error.code];
    }
    return (
      (error && error.message) ||
      "An unknown error occurred during biometric verification."
    );
  }
}
