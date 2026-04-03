import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["subNav", "chevron"];
  static values = { expanded: Boolean };

  connect() {
    // Auto-expand if this is the current team
    if (this.element.dataset.currentTeam === "true") {
      this.expand();
    }
  }

  toggle(event) {
    event.preventDefault();
    event.stopPropagation();

    if (this.expandedValue) {
      this.collapse();
    } else {
      this.expand();
    }
  }

  expand() {
    this.expandedValue = true;
    this.subNavTarget.classList.remove("hidden");
    this.chevronTarget.classList.add("-rotate-90");
  }

  collapse() {
    this.expandedValue = false;
    this.subNavTarget.classList.add("hidden");
    this.chevronTarget.classList.remove("-rotate-90");
  }
}
