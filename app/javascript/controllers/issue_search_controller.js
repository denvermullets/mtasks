import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input"];

  connect() {
    this.boundHandleKeyPress = this.handleKeyPress.bind(this);
    document.addEventListener("keydown", this.boundHandleKeyPress);
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeyPress);
    clearTimeout(this.inputTimeout);
  }

  handleKeyPress(event) {
    const isModifier = (event.metaKey || event.ctrlKey) && event.shiftKey;
    const isF = event.code === "KeyF" || event.key === "f" || event.key === "F";

    if (isModifier && isF) {
      event.preventDefault();
      this.inputTarget.focus();
      this.inputTarget.select();
    }
  }

  onInput() {
    clearTimeout(this.inputTimeout);
    this.inputTimeout = setTimeout(() => {
      this.applyQuery(this.inputTarget.value);
    }, 300);
  }

  onEscape(event) {
    event.preventDefault();
    this.inputTarget.value = "";
    clearTimeout(this.inputTimeout);
    this.applyQuery("");
    this.inputTarget.blur();
  }

  applyQuery(value) {
    const url = new URL(window.location.href);
    const trimmed = value.trim();
    if (trimmed) {
      url.searchParams.set("q", trimmed);
    } else {
      url.searchParams.delete("q");
    }
    window.history.pushState({}, "", url.toString());
    window.Turbo.visit(url.toString(), { frame: "issues_board" });
  }
}
