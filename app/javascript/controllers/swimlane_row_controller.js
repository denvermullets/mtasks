import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["content", "chevron"];

  toggle(event) {
    event.preventDefault();
    this.contentTarget.classList.toggle("hidden");
    this.chevronTarget.classList.toggle("-rotate-90");
  }
}
