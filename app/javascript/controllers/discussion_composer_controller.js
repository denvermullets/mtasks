import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["toggle", "hiddenInput", "label"];

  connect() {
    this.enabled = false;
    this.render();
  }

  toggle(event) {
    event.preventDefault();
    this.enabled = !this.enabled;
    this.render();
  }

  render() {
    this.hiddenInputTarget.value = this.enabled ? "1" : "0";
    this.toggleTarget.setAttribute("aria-pressed", this.enabled ? "true" : "false");
    if (this.enabled) {
      this.toggleTarget.classList.add("bg-accent/20", "text-accent", "border-accent/40");
      this.toggleTarget.classList.remove("text-gray-500", "border-stroke");
    } else {
      this.toggleTarget.classList.remove("bg-accent/20", "text-accent", "border-accent/40");
      this.toggleTarget.classList.add("text-gray-500", "border-stroke");
    }
  }
}
