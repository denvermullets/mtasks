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
    const drawer = document.getElementById("notification-drawer");
    const panel = document.getElementById("notification-drawer-panel");
    if (!drawer || !panel) return;

    this.openValue = true;
    drawer.classList.remove("hidden");
    // Trigger reflow for animation
    panel.offsetHeight;
    panel.classList.remove("translate-x-full");
    panel.classList.add("translate-x-0");
  }

  close() {
    const drawer = document.getElementById("notification-drawer");
    const panel = document.getElementById("notification-drawer-panel");
    if (!drawer || !panel) return;

    this.openValue = false;
    panel.classList.remove("translate-x-0");
    panel.classList.add("translate-x-full");

    setTimeout(() => {
      if (!this.openValue) {
        drawer.classList.add("hidden");
      }
    }, 200);
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.openValue) {
      this.close();
    }
  }
}
