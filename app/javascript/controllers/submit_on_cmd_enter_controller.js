import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  submit(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault();
      this.element.requestSubmit();
    }
  }
}
