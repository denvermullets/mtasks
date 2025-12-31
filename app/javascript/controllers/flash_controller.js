import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    // Auto-close after 5 seconds
    this.timeout = setTimeout(() => {
      this.close();
    }, 5000);
  }

  disconnect() {
    clearTimeout(this.timeout);
  }

  close() {
    this.element.remove();
  }
}
