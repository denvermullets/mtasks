import { Controller } from "@hotwired/stimulus";
import { trackEngagement } from "vektis";

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

  showModal(event) {
    this.modalTarget.classList.remove("hidden");

    // Two entry points land here: ⌘K via toggleModal(), which calls this with no argument, and
    // the sidebar's click->keyboard-shortcuts#showModal, which Stimulus always calls with an
    // event. `shortcut` is only true of the first, so it only ships there — §5.2 is a closed set.
    const properties = { via: event ? "web" : "keyboard", surface: "modal" };
    if (!event) properties.shortcut = "cmd_k";

    trackEngagement("keyboard-shortcut", "open", properties);
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
