import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["form", "status"];

  preview(event) {
    document.documentElement.dataset.theme = event.target.value;
    this.formTarget.requestSubmit();
  }

  previewFont(event) {
    document.documentElement.dataset.font = event.target.value;
    this.formTarget.requestSubmit();
  }

  saved(event) {
    if (!this.hasStatusTarget) return;

    const ok = event.detail.success;
    this.statusTarget.textContent = ok ? "Saved" : "Couldn't save — try again";
    this.statusTarget.classList.toggle("text-accent", ok);
    this.statusTarget.classList.toggle("text-red-400", !ok);
    this.statusTarget.classList.remove("opacity-0");

    clearTimeout(this.hideTimer);
    if (!ok) return;

    this.hideTimer = setTimeout(() => {
      this.statusTarget.classList.add("opacity-0");
    }, 2000);
  }

  disconnect() {
    clearTimeout(this.hideTimer);
  }
}
