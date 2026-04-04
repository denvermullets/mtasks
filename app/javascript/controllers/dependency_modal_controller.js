import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["modal", "search", "frame", "title", "directionInput"];
  static values = { searchUrl: String };

  open(event) {
    const direction = event.params.direction;
    this.directionInputTarget.value = direction;
    this.titleTarget.textContent =
      direction === "blocked_by" ? "Add blocked by issues" : "Add blocking issues";

    this.modalTarget.classList.remove("hidden");
    this.searchTarget.value = "";
    this.searchTarget.focus();

    this.frameTarget.src = `${this.searchUrlValue}?q=`;

    this.boundEscape = this.handleKeydown.bind(this);
    document.addEventListener("keydown", this.boundEscape);
  }

  close() {
    this.modalTarget.classList.add("hidden");
    this.searchTarget.value = "";
    document.removeEventListener("keydown", this.boundEscape);
  }

  search() {
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      const query = this.searchTarget.value.trim();
      this.frameTarget.src = `${this.searchUrlValue}?q=${encodeURIComponent(query)}`;
    }, 300);
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close();
    }
  }

  closeOnBackdrop(event) {
    if (event.target === event.currentTarget) {
      this.close();
    }
  }

  disconnect() {
    clearTimeout(this.debounceTimer);
    document.removeEventListener("keydown", this.boundEscape);
  }
}
