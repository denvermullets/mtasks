import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["overlay", "image"];

  connect() {
    this.boundHandleKeyDown = this.handleKeyDown.bind(this);
  }

  open(event) {
    event.preventDefault();
    const url = event.currentTarget.dataset.lightboxUrl;
    const filename = event.currentTarget.dataset.lightboxFilename || "";

    this.imageTarget.src = url;
    this.imageTarget.alt = filename;
    this.overlayTarget.classList.remove("hidden");
    document.body.classList.add("overflow-hidden");
    document.addEventListener("keydown", this.boundHandleKeyDown);
  }

  close() {
    this.overlayTarget.classList.add("hidden");
    this.imageTarget.src = "";
    document.body.classList.remove("overflow-hidden");
    document.removeEventListener("keydown", this.boundHandleKeyDown);
  }

  closeOnOverlay(event) {
    if (event.target === this.overlayTarget) {
      this.close();
    }
  }

  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.close();
    }
  }
}
