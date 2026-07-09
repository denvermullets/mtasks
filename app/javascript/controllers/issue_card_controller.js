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
    if (this.pickerOpen) return;

    // A missed mouseleave (overlay covering the card, board re-render) can leave a
    // stale marker behind, and lookups take the first match in DOM order.
    document.querySelectorAll('[data-hovered="true"]').forEach((card) => {
      if (card !== this.element) delete card.dataset.hovered;
    });

    // Mark this card as hovered so keyboard shortcuts can target it
    this.element.dataset.hovered = "true";
  }

  mouseLeave() {
    if (this.pickerOpen) return;

    // Remove hover state
    delete this.element.dataset.hovered;
  }

  // An open picker owns the hover context: reaching for its menu drags the cursor
  // across other cards, which would otherwise retarget the pending change.
  get pickerOpen() {
    return document.querySelector("[data-shared-picker]:not(.hidden)") !== null;
  }
}
