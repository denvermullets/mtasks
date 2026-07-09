import { Controller } from "@hotwired/stimulus";

// Copies `text` to the clipboard and briefly swaps the icon for a checkmark.
export default class extends Controller {
  static targets = ["idle", "done"];
  static values = { text: String };

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => this.flash());
  }

  flash() {
    clearTimeout(this.timeout);
    this.idleTarget.classList.add("hidden");
    this.doneTarget.classList.remove("hidden");
    this.timeout = setTimeout(() => {
      this.doneTarget.classList.add("hidden");
      this.idleTarget.classList.remove("hidden");
    }, 1500);
  }

  disconnect() {
    clearTimeout(this.timeout);
  }
}
