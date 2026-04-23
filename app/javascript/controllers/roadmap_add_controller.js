import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = ["modal", "chip"];
  static values = { teamId: Number, lane: { type: String, default: "now" } };

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    this.boundHandleEscape = this.handleEscape.bind(this);
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleEscape);
  }

  open(event) {
    const lane = event.currentTarget?.dataset.lane;
    if (lane) this.laneValue = lane;
    this.modalTarget.classList.remove("hidden");
    document.addEventListener("keydown", this.boundHandleEscape);
  }

  close() {
    this.modalTarget.classList.add("hidden");
    document.removeEventListener("keydown", this.boundHandleEscape);
  }

  backdropClick(event) {
    if (event.target === event.currentTarget) this.close();
  }

  selectLane(event) {
    this.laneValue = event.currentTarget.dataset.lane;
  }

  laneValueChanged() {
    this.chipTargets.forEach((chip) => {
      const active = chip.dataset.lane === this.laneValue;
      chip.classList.toggle("bg-accent", active);
      chip.classList.toggle("text-gray-900", active);
      chip.classList.toggle("border-accent", active);
      chip.classList.toggle("text-gray-400", !active);
      chip.classList.toggle("border-stroke", !active);
    });
  }

  async add(event) {
    const button = event.currentTarget;
    const projectId = button.dataset.projectId;
    if (!projectId) return;

    button.disabled = true;
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
            project: { roadmap_commitment: this.laneValue },
          }),
        }
      );

      if (response.ok) {
        Turbo.visit(window.location.href, { action: "replace" });
      } else {
        button.disabled = false;
        console.error("Failed to add project to roadmap", response.status);
      }
    } catch (error) {
      button.disabled = false;
      console.error("Error adding project to roadmap:", error);
    }
  }

  handleEscape(event) {
    if (event.key === "Escape") this.close();
  }
}
