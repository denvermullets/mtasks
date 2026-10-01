import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

// Drag-and-drop reordering of a dashboard's groups. Saves every group id in its new order; the
// page already shows the result, so the response carries nothing.
export default class extends Controller {
  static values = { url: String };

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    this.sortable = Sortable.create(this.element, {
      animation: 150,
      handle: "[data-dashboard-group-handle]",
      draggable: "[data-group-id]",
      onEnd: (event) => {
        if (event.oldIndex !== event.newIndex) this.save();
      },
    });
  }

  disconnect() {
    this.sortable?.destroy();
    this.sortable = null;
  }

  async save() {
    const body = new FormData();
    this.element.querySelectorAll("[data-group-id]").forEach((el) => body.append("ids[]", el.dataset.groupId));

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: { "X-CSRF-Token": this.csrfToken },
        body,
      });
      if (!response.ok) console.error("Failed to save group order", response.status);
    } catch (error) {
      console.error("Error saving group order:", error);
    }
  }
}
