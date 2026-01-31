import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["form"];

  toggle() {
    this.formTarget.classList.toggle("hidden");
    if (!this.formTarget.classList.contains("hidden")) {
      const textarea = this.formTarget.querySelector("textarea");
      if (textarea) {
        textarea.style.height = "auto";
        textarea.style.height = textarea.scrollHeight + "px";
        textarea.focus();
      }
    }
  }

  hide() {
    this.formTarget.classList.add("hidden");
  }
}
