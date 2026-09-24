import { Controller } from "@hotwired/stimulus";

// Lives on <body>. One modal (dashboards/_form_modal) serves both create (sidebar "+") and
// rename (dashboard menu); triggers pass url/method/name/description/title/submit as action params.
export default class extends Controller {
  static targets = ["modal", "form", "method", "title", "submit", "name", "description", "errors"];

  connect() {
    this.boundHandleEscape = this.handleEscape.bind(this);
    // The server re-rendered the modal open after a 422: wire Escape + focus as if the user opened it.
    if (this.hasModalTarget && !this.modalTarget.classList.contains("hidden")) this.show();
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleEscape);
  }

  open(event) {
    const {
      url,
      method = "post",
      name = "",
      description = "",
      title = "New dashboard",
      submit = "Create",
    } = event.params;

    this.formTarget.action = url;
    this.methodTarget.value = method;
    this.titleTarget.textContent = title;
    this.submitTarget.textContent = submit;
    this.nameTarget.value = name;
    this.descriptionTarget.value = description;
    if (this.hasErrorsTarget) this.errorsTarget.remove();
    this.show();
  }

  show() {
    this.modalTarget.classList.remove("hidden");
    document.addEventListener("keydown", this.boundHandleEscape);
    this.nameTarget.focus();
    this.nameTarget.select();
  }

  close() {
    this.modalTarget.classList.add("hidden");
    document.removeEventListener("keydown", this.boundHandleEscape);
  }

  backdropClick(event) {
    if (event.target === event.currentTarget) this.close();
  }

  handleEscape(event) {
    if (event.key === "Escape") this.close();
  }
}
