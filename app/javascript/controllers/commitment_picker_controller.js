import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = ["picker"];

  static values = {
    projectId: Number,
    teamId: Number,
    currentCommitment: String,
  };

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    this.boundHandleEscape = this.handleEscape.bind(this);
  }

  disconnect() {
    this.close();
  }

  open(event) {
    this.pickerTarget.classList.remove("hidden");
    this.positionOverlay(event?.currentTarget);
    document.addEventListener("click", this.boundHandleClickOutside);
    document.addEventListener("keydown", this.boundHandleEscape);
  }

  close() {
    this.pickerTarget.classList.add("hidden");
    document.removeEventListener("click", this.boundHandleClickOutside);
    document.removeEventListener("keydown", this.boundHandleEscape);
  }

  handleClickOutside(event) {
    if (!this.pickerTarget.contains(event.target) && !this.element.contains(event.target)) {
      this.close();
    } else if (!this.pickerTarget.contains(event.target)) {
      // click inside card but outside picker
      const trigger = event.target.closest('[data-action*="commitment-picker#open"]');
      if (!trigger) this.close();
    }
  }

  handleEscape(event) {
    if (event.key === "Escape") this.close();
  }

  async select(event) {
    const value = event.target.value || null;
    if (value === (this.currentCommitmentValue || null)) {
      this.close();
      return;
    }
    this.close();

    try {
      const response = await fetch(
        `/teams/${this.teamIdValue}/projects/${this.projectIdValue}`,
        {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            Accept: "text/vnd.turbo-stream.html",
            "X-CSRF-Token": this.csrfToken,
          },
          body: JSON.stringify({ project: { roadmap_commitment: value } }),
        }
      );

      if (response.ok) {
        Turbo.visit(window.location.href, { action: "replace" });
      } else {
        console.error("Failed to update roadmap commitment", response.status);
      }
    } catch (error) {
      console.error("Error updating roadmap commitment:", error);
    }
  }

  positionOverlay(trigger) {
    const overlayWidth = 288; // w-72
    const overlayHeight = 240;
    const reference = trigger || this.element;
    const rect = reference.getBoundingClientRect();

    let top = rect.bottom + 4;
    let left = rect.right - overlayWidth;

    if (left < 8) left = 8;
    if (left + overlayWidth > window.innerWidth - 8) {
      left = window.innerWidth - overlayWidth - 8;
    }
    if (top + overlayHeight > window.innerHeight) {
      top = rect.top - overlayHeight - 4;
    }
    if (top < 8) top = 8;

    this.pickerTarget.style.top = `${top}px`;
    this.pickerTarget.style.left = `${left}px`;
  }
}
