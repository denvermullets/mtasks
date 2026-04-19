import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["section", "toggleIcon", "mergeRules", "template"];

  toggle() {
    this.sectionTarget.classList.toggle("hidden");
    if (this.hasToggleIconTarget) {
      this.toggleIconTarget.classList.toggle("rotate-180");
    }
  }

  addMergeRule(event) {
    event.preventDefault();
    const html = this.templateTarget.innerHTML;
    this.mergeRulesTarget.insertAdjacentHTML("beforeend", html);
  }

  removeMergeRule(event) {
    event.preventDefault();
    event.currentTarget.closest("[data-merge-rule-row]").remove();
  }
}
