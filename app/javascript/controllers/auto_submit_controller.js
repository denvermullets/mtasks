import { Controller } from "@hotwired/stimulus";

// Submits the form it's attached to. `submit` fires right away (change/blur), `debounce`
// waits for a pause in typing. Turbo re-focuses an [autofocus] input after the resulting
// render; `caretToEnd` (on focus) keeps the cursor where the user left off.
export default class extends Controller {
  disconnect() {
    clearTimeout(this.timer);
  }

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

  debounce() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.element.requestSubmit(), 300);
  }

  // Wired to the form's submit event so Enter inside the debounce window doesn't fire twice.
  cancel() {
    clearTimeout(this.timer);
  }

  caretToEnd({ target }) {
    const end = target.value.length;
    target.setSelectionRange(end, end);
  }
}
