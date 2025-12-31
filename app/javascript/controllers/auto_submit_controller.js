import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  submit(event) {
    // Get the form
    const form = this.element;

    // For text inputs, only submit if value changed
    if (event.target.tagName === "INPUT" && event.target.type === "text") {
      const originalValue = event.target.dataset.autoSubmitOriginalValue;
      if (event.target.value === originalValue) {
        return;
      }
    }

    // Submit the form
    form.requestSubmit();
  }
}
