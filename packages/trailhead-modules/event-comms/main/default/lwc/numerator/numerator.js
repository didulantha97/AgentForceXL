import { LightningElement, api } from "lwc";

export default class Numerator extends LightningElement {
  // @api counter = 0;
  _currentCount = 0;
  priorCount = 0;
  @api
  get counter() {
    return this._currentCount;
  }
  set counter(value) {
    this.priorCount = this._currentCount;
    this._currentCount = value;
  }
  handleIncrement() {
    this._currentCount++;
  }
  handleDecrement() {
    this._currentCount--;
  }
  handleMultiply(event) {
    const factor = event.detail;
    this._currentCount *= factor;
  }
  @api
  maximizeCounter() {
    this._currentCount += 1000000;
  }
}
