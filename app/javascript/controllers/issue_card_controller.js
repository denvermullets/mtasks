import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {}

  click(event) {
    // Issue navigation handled by link
  }

  contextMenu(event) {
    // TODO: Show context menu for quick actions
    // - Change status
    // - Assign to user
    // - Change priority
    // - Archive
  }

  mouseEnter() {
    // Mark this card as hovered so keyboard shortcuts can target it
    this.element.dataset.hovered = "true";
  }

  mouseLeave() {
    // Remove hover state
    delete this.element.dataset.hovered;
  }
}
