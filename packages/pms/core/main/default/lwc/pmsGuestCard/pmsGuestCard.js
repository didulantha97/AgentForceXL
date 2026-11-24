import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import getGuestCard from "@salesforce/apex/PMS_Guest360Controller.getGuestCard";
import CURRENCY from "@salesforce/i18n/currency";
import { errorMessage } from "c/pmsDateUtils";
import BOOKING_OBJECT from "@salesforce/schema/PMS_Booking__c";
import PRIMARY_CONTACT from "@salesforce/schema/PMS_Booking__c.Primary_Contact__c";
import CONTACT_OBJECT from "@salesforce/schema/Contact";

/**
 * Compact guest card for staff screens. Contact comes from the contactId property, or, on a booking
 * record page, from the booking's Primary Contact. Renders nothing when there is no contact.
 */
export default class PmsGuestCard extends NavigationMixin(LightningElement) {
  @api contactId;
  @api recordId;
  @api objectApiName;

  card;
  error;
  loaded = false;
  bookingContactId;
  lastContactId;
  currencyCode = CURRENCY;

  get isBookingPage() {
    return (
      !this.contactId &&
      !!this.recordId &&
      this.objectApiName === BOOKING_OBJECT.objectApiName
    );
  }
  get bookingRecordId() {
    return this.isBookingPage ? this.recordId : undefined;
  }
  get resolvedContactId() {
    if (this.contactId) {
      return this.contactId;
    }
    if (this.isBookingPage) {
      return this.bookingContactId;
    }
    if (this.recordId && this.objectApiName === CONTACT_OBJECT.objectApiName) {
      return this.recordId;
    }
    return undefined;
  }

  @wire(getRecord, { recordId: "$bookingRecordId", fields: [PRIMARY_CONTACT] })
  wiredBooking({ data }) {
    this.bookingContactId = data
      ? getFieldValue(data, PRIMARY_CONTACT)
      : undefined;
  }

  @wire(getGuestCard, { contactId: "$resolvedContactId" })
  wiredCard({ data, error }) {
    if (data) {
      this.card = data;
      this.error = undefined;
      this.loaded = true;
    } else if (error) {
      this.card = undefined;
      this.error = errorMessage(error);
      this.loaded = true;
    }
  }

  renderedCallback() {
    const id = this.resolvedContactId;
    if (id !== this.lastContactId) {
      this.lastContactId = id;
      if (this.card && this.card.contactId !== id) {
        this.card = undefined;
        this.error = undefined;
        this.loaded = false;
      }
    }
  }

  get hasContact() {
    return !!this.resolvedContactId;
  }
  get showLoading() {
    return this.hasContact && !this.loaded;
  }
  get showContent() {
    return this.hasContact && !!this.card;
  }
  get hasVip() {
    return !!(this.card && this.card.vipLevel);
  }
  get vipLabel() {
    return `VIP: ${this.card.vipLevel}`;
  }
  get idIcon() {
    return this.card && this.card.idVerified
      ? "utility:success"
      : "utility:warning";
  }
  get idText() {
    return this.card && this.card.idVerified
      ? "ID verified"
      : "ID not verified";
  }
  get hasDietary() {
    return !!(this.card && this.card.dietary);
  }
  get hasAccess() {
    return !!(this.card && this.card.accessibilityNeeds);
  }
  get preferences() {
    return ((this.card && this.card.topPreferences) || [])
      .slice(0, 3)
      .map((p, i) => ({
        key: p.preferenceId || `p${i}`,
        text: p.category ? `${p.category}: ${p.value}` : p.value
      }));
  }
  get hasPreferences() {
    return this.preferences.length > 0;
  }
  get showBalance() {
    return !!(
      this.card &&
      this.card.balanceAccessible &&
      this.card.balanceDue !== null &&
      this.card.balanceDue !== undefined
    );
  }

  handleOpen(e) {
    e.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: this.resolvedContactId,
        objectApiName: CONTACT_OBJECT.objectApiName,
        actionName: "view"
      }
    });
  }
}
