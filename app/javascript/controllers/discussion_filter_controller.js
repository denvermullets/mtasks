import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["stream", "toggle"];
  static values = { decisionsOnly: { type: Boolean, default: false } };

  toggleDecisionsOnly() {
    this.decisionsOnlyValue = !this.decisionsOnlyValue;
  }

  decisionsOnlyValueChanged() {
    if (this.hasStreamTarget) {
      this.streamTarget.classList.toggle("decisions-only", this.decisionsOnlyValue);
    }
    if (this.hasToggleTarget) {
      this.toggleTarget.classList.toggle("bg-accent/10", this.decisionsOnlyValue);
      this.toggleTarget.classList.toggle("text-accent", this.decisionsOnlyValue);
      this.toggleTarget.classList.toggle("border-accent/40", this.decisionsOnlyValue);
      this.toggleTarget.setAttribute("aria-pressed", this.decisionsOnlyValue);
    }
  }
}
