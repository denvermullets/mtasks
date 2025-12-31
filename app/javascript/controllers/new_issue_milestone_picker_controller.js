import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = [
    "picker",
    "search",
    "milestoneList",
    "createOption",
    "createText",
    "hiddenField",
  ];

  static values = {
    teamId: Number,
    selectedMilestoneId: Number,
  };

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;

    // Bind event handlers
    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    this.boundHandleEscape = this.handleEscape.bind(this);
  }

  disconnect() {
    this.close();
  }

  open() {
    // Show picker
    this.pickerTarget.classList.remove("hidden");

    // Position overlay
    this.positionOverlay();

    // Focus search input
    this.searchTarget.focus();

    // Add event listeners
    document.addEventListener("click", this.boundHandleClickOutside);
    document.addEventListener("keydown", this.boundHandleEscape);
  }

  close() {
    this.pickerTarget.classList.add("hidden");
    this.searchTarget.value = "";

    // Remove event listeners
    document.removeEventListener("click", this.boundHandleClickOutside);
    document.removeEventListener("keydown", this.boundHandleEscape);
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close();
    }
  }

  handleEscape(event) {
    if (event.key === "Escape") {
      this.close();
    }
  }

  filterMilestones() {
    const query = this.searchTarget.value.trim().toLowerCase();
    const milestoneOptions = this.milestoneListTarget.querySelectorAll(".milestone-option");

    if (query === "") {
      // Show all milestones
      milestoneOptions.forEach((el) => el.classList.remove("hidden"));
      this.createOptionTarget.classList.add("hidden");
      return;
    }

    // Filter milestones
    let exactMatch = false;

    milestoneOptions.forEach((el) => {
      const name = el.dataset.milestoneName.toLowerCase();
      if (name.includes(query)) {
        el.classList.remove("hidden");
        if (name === query) {
          exactMatch = true;
        }
      } else {
        el.classList.add("hidden");
      }
    });

    // Show create option if no exact match
    if (!exactMatch && query.length > 0) {
      this.createTextTarget.textContent = query;
      this.createOptionTarget.classList.remove("hidden");
    } else {
      this.createOptionTarget.classList.add("hidden");
    }
  }

  async createMilestone() {
    const name = this.searchTarget.value.trim();
    if (!name) return;

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/milestones`, {
        method: "POST",
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify({
          milestone: {
            name: name,
          },
        }),
      });

      if (response.ok) {
        const html = await response.text();
        Turbo.renderStreamMessage(html);

        // Wait for the DOM to update, then find and select the new milestone
        setTimeout(() => {
          const newMilestoneElement = Array.from(
            this.milestoneListTarget.querySelectorAll(".milestone-option")
          ).find((el) => el.dataset.milestoneName === name);

          if (newMilestoneElement) {
            const milestoneId = newMilestoneElement.dataset.milestoneId;
            const radio = newMilestoneElement.querySelector("input[type=radio]");
            radio.checked = true;

            // Update selected milestone
            this.selectedMilestoneIdValue = milestoneId === "" ? null : parseInt(milestoneId);
            this.updateHiddenField();
            this.updateButtonDisplay(name);
          }

          // Clear search
          this.searchTarget.value = "";
          this.filterMilestones();
        }, 100);
      } else {
        const error = await response.text();
        console.error("Failed to create milestone:", error);
      }
    } catch (error) {
      console.error("Failed to create milestone:", error);
    }
  }

  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.close();
    }
  }

  selectMilestone(event) {
    const milestoneOption = event.target.closest(".milestone-option");
    const milestoneId = milestoneOption.dataset.milestoneId;
    const milestoneName = milestoneOption.dataset.milestoneName;

    // Update selected milestone ID
    this.selectedMilestoneIdValue = milestoneId === "" ? null : parseInt(milestoneId);

    // Update hidden field
    this.updateHiddenField();

    // Update button display
    this.updateButtonDisplay(milestoneName);

    // Close picker
    this.close();
  }

  updateHiddenField() {
    // Find the hidden field target
    if (!this.hasHiddenFieldTarget) return;

    // Update the hidden field value
    this.hiddenFieldTarget.value = this.selectedMilestoneIdValue || "";
  }

  updateButtonDisplay(milestoneName) {
    // Update the button label to show milestone name
    const button = this.element.closest(".relative").querySelector("button");
    if (!button) return;

    const labelSpan = button.querySelector('[data-issue-form-target="milestoneLabel"]');
    if (!labelSpan) return;

    labelSpan.textContent = milestoneName || "No milestone";
  }

  positionOverlay() {
    // Get the button that triggered this
    const button = this.element.closest(".relative").querySelector("button");
    if (!button) return;

    const rect = button.getBoundingClientRect();
    const overlayWidth = 320; // w-80

    // Position below the button
    let top = rect.bottom + 4;
    let left = rect.left;

    // Check if overlay would go off-screen horizontally
    if (left + overlayWidth > window.innerWidth) {
      left = window.innerWidth - overlayWidth - 8;
    }
    if (left < 8) {
      left = 8;
    }

    this.pickerTarget.style.top = `${top}px`;
    this.pickerTarget.style.left = `${left}px`;
  }
}
