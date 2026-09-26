import { Controller } from "@hotwired/stimulus";

// Views menu on the issues board. Filter/display changes only pushState the URL (the top bar is
// never re-rendered), so each form copies the live query string into its hidden field on submit.
export default class extends Controller {
  static targets = ["panel", "name"];

  connect() {
    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    document.addEventListener("click", this.boundHandleClickOutside);
  }

  disconnect() {
    document.removeEventListener("click", this.boundHandleClickOutside);
  }

  togglePanel(event) {
    event.stopPropagation();
    this.panelTarget.classList.toggle("hidden");
    if (!this.panelTarget.classList.contains("hidden") && this.hasNameTarget) this.nameTarget.focus();
  }

  closePanel() {
    this.panelTarget.classList.add("hidden");
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) this.closePanel();
  }

  captureQuery(event) {
    const field = event.target.querySelector("input[name='saved_view[query]']");
    if (field) field.value = window.location.search;
  }
}
