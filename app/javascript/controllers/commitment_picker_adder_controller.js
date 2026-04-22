import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static values = {
    teamId: Number,
    commitment: String,
  };

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
  }

  async add(event) {
    const button = event.currentTarget;
    const projectId = button.dataset.projectId;
    if (!projectId) return;

    try {
      const response = await fetch(
        `/teams/${this.teamIdValue}/projects/${projectId}`,
        {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            Accept: "text/vnd.turbo-stream.html",
            "X-CSRF-Token": this.csrfToken,
          },
          body: JSON.stringify({
            project: { roadmap_commitment: this.commitmentValue },
          }),
        }
      );

      if (response.ok) {
        Turbo.visit(window.location.href, { action: "replace" });
      } else {
        console.error("Failed to add project to roadmap", response.status);
      }
    } catch (error) {
      console.error("Error adding project to roadmap:", error);
    }
  }
}
