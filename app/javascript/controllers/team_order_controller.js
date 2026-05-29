import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

// Drag-and-drop reordering of sidebar teams, auto-saving each change.
export default class extends Controller {
  static targets = ["list"];
  static values = { url: String };

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    this.sortables = this.listTargets.map((list) =>
      Sortable.create(list, {
        animation: 150,
        onEnd: () => this.save(list),
      })
    );
  }

  disconnect() {
    this.sortables?.forEach((sortable) => sortable.destroy());
    this.sortables = [];
  }

  async save(list) {
    const scope = list.dataset.scope;
    const ids = Array.from(list.querySelectorAll("[data-team-id]")).map((el) =>
      Number(el.dataset.teamId)
    );

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify({ scope, ids }),
      });
      if (response.ok) {
        const html = await response.text();
        window.Turbo.renderStreamMessage(html);
      } else {
        console.error("Failed to save team order", response.status);
      }
    } catch (error) {
      console.error("Error saving team order:", error);
    }
  }
}
