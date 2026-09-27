import { LightningElement, track } from "lwc";
import { getNfcService } from "lightning/mobileCapabilities";

const FAILURE_MESSAGES = {
  NFC_NOT_SUPPORTED: "This device does not support NFC.",
  NFC_NOT_ENABLED:
    "NFC is turned off. Enable it in your device settings and try again.",
  TAG_EMPTY: "The NFC tag contains no data.",
  SERVICE_NOT_ENABLED: "The NFC service is not enabled for this app."
};

const WRITE_TYPE_OPTIONS = [
  { label: "Text", value: "text" },
  { label: "URL", value: "uri" }
];

export default class NfcComponent extends LightningElement {
  @track readRecords = [];
  @track errorMessage = "";
  @track successMessage = "";
  @track isBusy = false;
  @track writeType = "text";
  @track writeValue = "";

  writeTypeOptions = WRITE_TYPE_OPTIONS;

  _nfc = null;
  _idCounter = 0;

  connectedCallback() {
    this._nfc = getNfcService();
  }

  get isAvailable() {
    return this._nfc != null && this._nfc.isAvailable();
  }

  get isWriteDisabled() {
    return this.isBusy || !this.writeValue.trim();
  }

  get writeInputLabel() {
    return this.writeType === "uri" ? "URL to write" : "Text to write";
  }

  get writeInputType() {
    return this.writeType === "uri" ? "url" : "text";
  }

  handleWriteTypeChange(event) {
    this.writeType = event.detail.value;
  }

  handleWriteValueChange(event) {
    this.writeValue = event.detail.value;
  }

  async handleRead() {
    await this._run(async () => {
      const messages = await this._nfc.read({
        instructionText: "Hold your device near an NFC tag to read it.",
        successText: "Tag read successfully."
      });
      this.readRecords = this._toDisplayRecords(messages);
      this.successMessage = `Read ${this.readRecords.length} record(s) from the tag.`;
    });
  }

  async handleWrite() {
    await this._run(async () => {
      const value = this.writeValue.trim();
      const record =
        this.writeType === "uri"
          ? await this._nfc.createUriRecord(value)
          : await this._nfc.createTextRecord({ text: value, langId: "en" });
      await this._nfc.write([record], {
        instructionText: "Hold your device near an NFC tag to write to it.",
        successText: "Tag written successfully."
      });
      this.successMessage = "Data written to the NFC tag.";
      this.writeValue = "";
    });
  }

  async handleErase() {
    await this._run(async () => {
      await this._nfc.erase({
        instructionText: "Hold your device near an NFC tag to erase it.",
        successText: "Tag erased successfully."
      });
      this.successMessage = "The NFC tag was erased.";
    });
  }

  handleClear() {
    this.readRecords = [];
    this.successMessage = "";
  }

  async _run(operation) {
    this.errorMessage = "";
    this.successMessage = "";
    this.isBusy = true;
    try {
      await operation();
    } catch (error) {
      // Dismissing the NFC sheet is a user choice, not an error worth surfacing.
      if (!error || error.code !== "USER_DISMISSED") {
        this.errorMessage = this._formatError(error);
      }
    } finally {
      this.isBusy = false;
    }
  }

  _toDisplayRecords(messages) {
    const records = [];
    (messages || []).forEach((message) => {
      (message.records || []).forEach((record) => {
        const source = record.parsed || record.raw;
        records.push({
          id: ++this._idCounter,
          value: record.parsed
            ? source.payload
            : this._decodeBase64(source.payload),
          format: source.typeNameFormat,
          type: source.type
        });
      });
    });
    return records;
  }

  _decodeBase64(value) {
    try {
      return atob(value);
    } catch {
      return value;
    }
  }

  _formatError(error) {
    if (error && FAILURE_MESSAGES[error.code]) {
      return FAILURE_MESSAGES[error.code];
    }
    return (
      (error && error.message) ||
      "An unknown error occurred while accessing the NFC tag."
    );
  }
}
