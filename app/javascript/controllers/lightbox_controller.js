import { Controller } from "@hotwired/stimulus";
import { trackEngagement } from "vektis";

export default class extends Controller {
  static targets = ["overlay", "image"];
  static values = { surface: String };

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

    // Neither the URL nor the filename ships — attachment filenames are banned (taxonomy §6.1).
    // The browser owns only the `view` half of issue-attachment; create/remove are the server's (§9).
    const properties = {};
    if (this.surfaceValue) properties.surface = this.surfaceValue;
    trackEngagement("issue-attachment", "view", properties);
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
