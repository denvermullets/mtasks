import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  preview(event) {
    document.documentElement.dataset.theme = event.target.value;
  }

  previewFont(event) {
    document.documentElement.dataset.font = event.target.value;
  }
}
