import { Controller } from "@hotwired/stimulus";

// Collapses a user-defined sidebar team group and remembers the state on the server.
export default class extends Controller {
  static targets = ["list", "chevron"];
  static values = { url: String };

  toggle(event) {
    event.preventDefault();
    const collapsed = this.listTarget.classList.toggle("hidden");
    this.chevronTarget.classList.toggle("rotate-180", collapsed);
    this.save(collapsed);
  }

  async save(collapsed) {
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        },
        body: JSON.stringify({ collapsed }),
      });
      if (!response.ok) console.error("Failed to save group state", response.status);
    } catch (error) {
      console.error("Error saving group state:", error);
    }
  }
}
