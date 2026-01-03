import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["modal"];

  connect() {
    this.boundHandleKeyPress = this.handleKeyPress.bind(this);
    document.addEventListener("keydown", this.boundHandleKeyPress);
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeyPress);
  }

  handleKeyPress(event) {
    // Ignore if user is typing in an input field
    if (event.target.matches("input, textarea, select")) {
      return;
    }

    // Check for Cmd+K (Mac) or Ctrl+K (Windows/Linux)
    if ((event.metaKey || event.ctrlKey) && event.key === "k") {
      event.preventDefault();
      this.toggleModal();
    }

    // Close modal with Escape
    if (event.key === "Escape" && this.isModalVisible()) {
      event.preventDefault();
      this.hideModal();
    }
  }

  toggleModal() {
    if (this.isModalVisible()) {
      this.hideModal();
    } else {
      this.showModal();
    }
  }

  showModal() {
    this.modalTarget.classList.remove("hidden");
  }

  hideModal() {
    this.modalTarget.classList.add("hidden");
  }

  isModalVisible() {
    return !this.modalTarget.classList.contains("hidden");
  }

  closeOnBackdrop(event) {
    // Close if clicking the backdrop (not the modal content)
    if (event.target === this.modalTarget) {
      this.hideModal();
    }
  }
}
