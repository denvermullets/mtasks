import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["colorInput"];

  selectColor(event) {
    event.preventDefault();
    const color = event.currentTarget.dataset.color;
    if (this.hasColorInputTarget) {
      this.colorInputTarget.value = color;
    }
  }
}
