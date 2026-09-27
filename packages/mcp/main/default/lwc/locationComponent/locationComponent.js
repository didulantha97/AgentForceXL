import { LightningElement, track } from "lwc";
import { getLocationService } from "lightning/mobileCapabilities";

const LOCATION_OPTIONS = {
  enableHighAccuracy: true,
  permissionRationaleText:
    "Allow location access to show your current position."
};

const FAILURE_MESSAGES = {
  LOCATION_SERVICE_DISABLED:
    "Location services are turned off on this device. Turn them on in your device settings.",
  USER_DENIED_PERMISSION:
    "Location permission was denied. Try again and allow access when prompted.",
  USER_DISABLED_PERMISSION:
    "Location access is disabled for this app. Turn it on in your device settings.",
  SERVICE_NOT_ENABLED: "The location service is not enabled for this app."
};

export default class LocationComponent extends LightningElement {
  @track position = null;
  @track errorMessage = "";
  @track isLocating = false;
  @track isWatching = false;

  _location = null;
  _watchId = null;

  connectedCallback() {
    this._location = getLocationService();
  }

  disconnectedCallback() {
    this._stopWatching();
  }

  get isAvailable() {
    return this._location != null && this._location.isAvailable();
  }

  get isGetDisabled() {
    return this.isLocating || this.isWatching;
  }

  get watchButtonLabel() {
    return this.isWatching ? "Stop Tracking" : "Start Tracking";
  }

  get watchButtonIcon() {
    return this.isWatching ? "utility:stop" : "utility:play";
  }

  get watchButtonVariant() {
    return this.isWatching ? "destructive" : "brand-outline";
  }

  get mapMarkers() {
    if (!this.position) {
      return [];
    }
    return [
      {
        location: {
          Latitude: this.position.latitude,
          Longitude: this.position.longitude
        },
        title: "Current Location"
      }
    ];
  }

  async handleGetLocation() {
    this.errorMessage = "";
    this.isLocating = true;
    try {
      const result = await this._location.getCurrentPosition(LOCATION_OPTIONS);
      this._setPosition(result);
    } catch (error) {
      this.errorMessage = this._formatError(error);
    } finally {
      this.isLocating = false;
    }
  }

  handleToggleWatch() {
    if (this.isWatching) {
      this._stopWatching();
      return;
    }
    this.errorMessage = "";
    this._watchId = this._location.startWatchingPosition(
      LOCATION_OPTIONS,
      (result, failure) => {
        if (failure) {
          this.errorMessage = this._formatError(failure);
          this._stopWatching();
        } else if (result) {
          this.errorMessage = "";
          this._setPosition(result);
        }
      }
    );
    this.isWatching = true;
  }

  handleClear() {
    this.position = null;
  }

  _stopWatching() {
    if (this._watchId !== null && this._location) {
      this._location.stopWatchingPosition(this._watchId);
    }
    this._watchId = null;
    this.isWatching = false;
  }

  _setPosition(result) {
    const { coords, timestamp } = result;
    this.position = {
      latitude: coords.latitude,
      longitude: coords.longitude,
      latitudeText: coords.latitude.toFixed(6),
      longitudeText: coords.longitude.toFixed(6),
      accuracyText: this._formatNumber(coords.accuracy, "m"),
      altitudeText: this._formatNumber(coords.altitude, "m"),
      speedText: this._formatNumber(coords.speed, "m/s"),
      headingText: this._formatNumber(coords.heading, "°"),
      timeText: new Date(timestamp).toLocaleTimeString()
    };
  }

  _formatNumber(value, unit) {
    return value === undefined || value === null || Number.isNaN(value)
      ? "—"
      : `${value.toFixed(1)} ${unit}`;
  }

  _formatError(error) {
    if (error && FAILURE_MESSAGES[error.code]) {
      return FAILURE_MESSAGES[error.code];
    }
    return (
      (error && error.message) ||
      "An unknown error occurred while getting your location."
    );
  }
}
