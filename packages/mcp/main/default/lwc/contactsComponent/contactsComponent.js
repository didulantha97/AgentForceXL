import { LightningElement, track } from "lwc";
import { getContactsService } from "lightning/mobileCapabilities";

const CONTACTS_OPTIONS = {
  permissionRationaleText:
    "Allow access to your contacts to pick or save a contact."
};

const FAILURE_MESSAGES = {
  USER_DENIED_PERMISSION:
    "Contacts permission was denied. Try again and allow access when prompted.",
  USER_DISABLED_PERMISSION:
    "Contacts access is disabled for this app. Turn it on in your device settings.",
  USER_RESTRICTED_PERMISSION:
    "This app is restricted from accessing contacts on this device.",
  SERVICE_NOT_ENABLED: "The contacts service is not enabled for this app.",
  SAVE_OPERATION_FAILED: "The contact could not be saved to your address book."
};

const EMPTY_FORM = {
  givenName: "",
  familyName: "",
  phone: "",
  email: "",
  company: ""
};

export default class ContactsComponent extends LightningElement {
  @track pickedContacts = [];
  @track form = { ...EMPTY_FORM };
  @track errorMessage = "";
  @track successMessage = "";
  @track isBusy = false;

  _contacts = null;

  connectedCallback() {
    this._contacts = getContactsService();
  }

  get isAvailable() {
    return this._contacts != null && this._contacts.isAvailable();
  }

  get isSaveDisabled() {
    return (
      this.isBusy ||
      !(this.form.givenName.trim() || this.form.familyName.trim())
    );
  }

  handleFieldChange(event) {
    const field = event.target.dataset.field;
    this.form = { ...this.form, [field]: event.detail.value };
  }

  async handlePick() {
    await this._run(async () => {
      const contacts = await this._contacts.getContacts(CONTACTS_OPTIONS);
      this.pickedContacts = (contacts || []).map((contact, index) =>
        this._toDisplayContact(contact, index)
      );
      if (this.pickedContacts.length) {
        this.dispatchEvent(
          new CustomEvent("contactspicked", { detail: { contacts } })
        );
      }
    });
  }

  async handleSave() {
    await this._run(async () => {
      const { givenName, familyName, phone, email, company } = this.form;
      const contact = {
        id: "",
        name: {
          givenName: givenName.trim(),
          familyName: familyName.trim(),
          middleName: "",
          namePrefix: "",
          nameSuffix: ""
        },
        phoneNumbers: phone.trim()
          ? [{ label: "mobile", value: phone.trim() }]
          : [],
        emails: email.trim() ? [{ label: "work", value: email.trim() }] : [],
        addresses: [],
        ims: [],
        organizations: company.trim()
          ? [{ name: company.trim(), department: "", title: "" }]
          : [],
        note: "",
        urls: []
      };
      await this._contacts.putContact(contact, CONTACTS_OPTIONS);
      this.successMessage = `${this._fullName(contact.name)} was saved to your contacts.`;
      this.form = { ...EMPTY_FORM };
    });
  }

  handleClear() {
    this.pickedContacts = [];
  }

  async _run(operation) {
    this.errorMessage = "";
    this.successMessage = "";
    this.isBusy = true;
    try {
      await operation();
    } catch (error) {
      // Cancelling the contact picker is a user choice, not an error worth surfacing.
      if (!error || error.code !== "USER_DISMISSED") {
        this.errorMessage = this._formatError(error);
      }
    } finally {
      this.isBusy = false;
    }
  }

  _toDisplayContact(contact, index) {
    const org = (contact.organizations || [])[0];
    return {
      id: `${index}-${contact.id || ""}`,
      fullName: this._fullName(contact.name) || "Unnamed contact",
      organization: org ? [org.title, org.name].filter(Boolean).join(", ") : "",
      phones: (contact.phoneNumbers || []).map((p, i) => ({
        key: `p${i}`,
        label: p.label,
        value: p.value
      })),
      emails: (contact.emails || []).map((e, i) => ({
        key: `e${i}`,
        label: e.label,
        value: e.value
      }))
    };
  }

  _fullName(name) {
    if (!name) {
      return "";
    }
    return [
      name.namePrefix,
      name.givenName,
      name.middleName,
      name.familyName,
      name.nameSuffix
    ]
      .filter(Boolean)
      .join(" ");
  }

  _formatError(error) {
    if (error && FAILURE_MESSAGES[error.code]) {
      return FAILURE_MESSAGES[error.code];
    }
    return (
      (error && error.message) ||
      "An unknown error occurred while accessing contacts."
    );
  }
}
