import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

// Drag-and-drop reordering of a team's lanes on the team settings page.
export default class extends Controller {
  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    this.sortable = Sortable.create(this.element, {
      animation: 150,
      handle: "[data-lane-order-handle]",
      onEnd: (event) => {
        if (event.oldIndex !== event.newIndex) this.save(event.item, event.newIndex);
      },
    });
  }

  disconnect() {
    this.sortable?.destroy();
    this.sortable = null;
  }

  async save(item, position) {
    const body = new FormData();
    body.append("lane[position]", position);

    try {
      const response = await fetch(item.dataset.laneUrl, {
        method: "PATCH",
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.csrfToken,
        },
        body,
      });
      if (response.ok) {
        window.Turbo.renderStreamMessage(await response.text());
      } else {
        console.error("Failed to save lane order", response.status);
      }
    } catch (error) {
      console.error("Error saving lane order:", error);
    }
  }
}
