import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["drawer", "panel"];
  static values = { open: Boolean };

  connect() {
    this.openValue = false;
    this.boundHandleKeydown = this.handleKeydown.bind(this);
    document.addEventListener("keydown", this.boundHandleKeydown);
    this.boundClose = this.close.bind(this);
    document.addEventListener("turbo:before-render", this.boundClose);
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeydown);
    document.removeEventListener("turbo:before-render", this.boundClose);
  }

  toggle() {
    if (this.openValue) {
      this.close();
    } else {
      this.open();
    }
  }

  open() {
    if (!this.hasDrawerTarget || !this.hasPanelTarget) return;

    this.openValue = true;
    this.drawerTarget.classList.remove("hidden");
    this.panelTarget.offsetHeight;
    this.panelTarget.classList.remove("translate-x-full");
    this.panelTarget.classList.add("translate-x-0");
    document.body.classList.add("overflow-hidden");
  }

  close() {
    if (!this.hasDrawerTarget || !this.hasPanelTarget) return;

    this.openValue = false;
    this.panelTarget.classList.remove("translate-x-0");
    this.panelTarget.classList.add("translate-x-full");
    document.body.classList.remove("overflow-hidden");

    setTimeout(() => {
      if (!this.openValue) {
        this.drawerTarget.classList.add("hidden");
      }
    }, 200);
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.openValue) {
      this.close();
    }
  }
}
