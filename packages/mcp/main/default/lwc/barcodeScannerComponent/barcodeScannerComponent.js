import { LightningElement, track } from "lwc";
import { getBarcodeScanner } from "lightning/mobileCapabilities";

export default class BarcodeScannerComponent extends LightningElement {
  @track scannedBarcodes = [];
  @track errorMessage = "";
  @track isScanning = false;

  _scanner = null;
  _idCounter = 0;

  connectedCallback() {
    this._scanner = getBarcodeScanner();
  }

  get isAvailable() {
    return this._scanner != null && this._scanner.isAvailable();
  }

  async handleScan() {
    this.errorMessage = "";
    this.isScanning = true;

    const options = {
      barcodeTypes: [
        "qr",
        "ean13",
        "ean8",
        "upca",
        "upce",
        "code128",
        "code39",
        "code93",
        "datamatrix",
        "pdf417",
        "itf"
      ],
      instructionText: "Point the camera at a barcode",
      successText: "Barcode captured!",
      showSuccessCheckMark: true,
      vibrateOnSuccess: true,
      scannerSize: "LARGE",
      cameraFacing: "BACK",
      enableFlashlight: true,
      previewBarcodeData: true
    };

    try {
      const results = await this._scanner.scan(options);
      results.forEach((barcode) => {
        this.scannedBarcodes = [
          ...this.scannedBarcodes,
          { id: ++this._idCounter, type: barcode.type, value: barcode.value }
        ];
      });
    } catch (error) {
      this.errorMessage = this._resolveErrorMessage(error.code);
    } finally {
      this.isScanning = false;
      this._scanner.dismiss();
    }
  }

  handleCopy(event) {
    const value = event.currentTarget.dataset.value;
    if (navigator.clipboard) {
      navigator.clipboard.writeText(value).catch(() => {});
    }
  }

  handleClear() {
    this.scannedBarcodes = [];
    this.errorMessage = "";
  }

  _resolveErrorMessage(code) {
    switch (code) {
      case "USER_DISMISSED":
        return "";
      case "USER_DENIED_PERMISSION":
        return "Camera permission was denied. Please allow camera access when prompted and try again.";
      case "USER_DISABLED_PERMISSION":
        return "Camera access is disabled. Go to your device Settings > Privacy > Camera and enable it for this app.";
      case "INVALID_BARCODE_TYPE_REQUESTED":
        return "An unsupported barcode type was requested. Please contact your administrator.";
      case "SERVICE_NOT_ENABLED":
        return "The Barcode Scanner service is not enabled for this org. Contact your Salesforce administrator.";
      case "UNKNOWN_REASON":
      default:
        return "An unexpected error occurred while scanning. Please try again.";
    }
  }
}
