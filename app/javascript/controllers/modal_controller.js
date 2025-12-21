import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Add escape key listener
    this.boundHandleEscape = this.handleEscape.bind(this)
    document.addEventListener("keydown", this.boundHandleEscape)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleEscape)
  }

  close() {
    this.element.remove()
  }

  handleEscape(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}
