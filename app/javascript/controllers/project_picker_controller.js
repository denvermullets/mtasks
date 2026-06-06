import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = [
    "picker",
    "search",
    "projectList",
    "emptyState",
    "header",
  ];

  static values = {
    issueId: Number,
    teamId: Number,
    context: String,
    currentProject: Number,
  };

  connect() {
    this.currentFocusIndex = -1;
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;

    // Bind event handlers
    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    this.boundHandleEscape = this.handleEscape.bind(this);

    // Set up debounced filter
    this.filterDebounceTimeout = null;
  }

  disconnect() {
    this.close();
  }

  // Shared-picker entry point: retarget this single picker at the hovered card,
  // then open. Used by board-keyboard for the 'P' shortcut so we don't render a
  // full project picker per issue row.
  openForCard(card) {
    this.referenceCard = card;
    this.issueIdValue = parseInt(card.dataset.issueId);

    const currentProjectId = parseInt(card.dataset.currentProjectId || "0") || 0;
    this.currentProjectValue = currentProjectId;

    if (this.hasHeaderTarget) {
      const identifier = card.dataset.issueIdentifier || "";
      const title = card.dataset.issueTitle || "";
      this.headerTarget.textContent = title ? `${identifier} • ${title}` : identifier;
    }

    // Reflect the issue's current project in the radio state
    this.projectListTarget.querySelectorAll('input[type="radio"]').forEach((radio) => {
      radio.checked =
        radio.value === String(currentProjectId) ||
        (radio.value === "" && currentProjectId === 0);
    });

    this.open();
  }

  open() {
    // Show picker
    this.pickerTarget.classList.remove("hidden");

    // Position overlay (for both card and sidebar contexts)
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
    this.currentFocusIndex = -1;

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

  filterProjects() {
    // Clear previous debounce timeout
    if (this.filterDebounceTimeout) {
      clearTimeout(this.filterDebounceTimeout);
    }

    // Debounce the filtering
    this.filterDebounceTimeout = setTimeout(() => {
      const query = this.searchTarget.value.trim().toLowerCase();
      const projectOptions = this.projectListTarget.querySelectorAll(".project-option");

      if (query === "") {
        // Show all projects
        projectOptions.forEach((el) => el.classList.remove("hidden"));
        this.updateEmptyState(projectOptions);
        return;
      }

      // Filter projects
      let visibleCount = 0;

      projectOptions.forEach((el) => {
        const name = el.dataset.projectName.toLowerCase();
        if (name.includes(query)) {
          el.classList.remove("hidden");
          visibleCount++;
        } else {
          el.classList.add("hidden");
        }
      });

      this.updateEmptyState(projectOptions);
      this.currentFocusIndex = -1;
    }, 300);
  }

  handleKeyDown(event) {
    // Don't interfere with normal typing
    if (!["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) {
      return;
    }

    event.preventDefault();

    if (event.key === "Escape") {
      this.close();
      return;
    }

    const visibleOptions = this.getVisibleOptions();

    if (event.key === "ArrowDown") {
      this.currentFocusIndex = Math.min(this.currentFocusIndex + 1, visibleOptions.length - 1);
      this.updateFocus(visibleOptions);
    } else if (event.key === "ArrowUp") {
      this.currentFocusIndex = Math.max(this.currentFocusIndex - 1, 0);
      this.updateFocus(visibleOptions);
    } else if (event.key === "Enter" && this.currentFocusIndex >= 0) {
      visibleOptions[this.currentFocusIndex].querySelector("input").click();
    }
  }

  getVisibleOptions() {
    return Array.from(this.projectListTarget.querySelectorAll(".project-option:not(.hidden)"));
  }

  updateFocus(options) {
    options.forEach((option, index) => {
      if (index === this.currentFocusIndex) {
        option.classList.add("bg-hover-highlight");
        option.scrollIntoView({ block: "nearest" });
      } else {
        option.classList.remove("bg-hover-highlight");
      }
    });
  }

  async selectProject(event) {
    const projectOption = event.target.closest(".project-option");
    const projectId = projectOption.dataset.projectId;

    await this.updateIssueProject(projectId === "" ? null : parseInt(projectId));
  }

  async updateIssueProject(projectId) {
    try {
      const response = await fetch(`/teams/${this.teamIdValue}/issues/${this.issueIdValue}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify({
          issue: {
            project_id: projectId,
          },
        }),
      });

      if (response.ok) {
        this.currentProjectValue = projectId || 0;

        // Process the turbo stream response
        const turboStream = await response.text();
        Turbo.renderStreamMessage(turboStream);

        // Close the picker after a short delay to allow the board to reload
        setTimeout(() => {
          if (this.hasPickerTarget && !this.pickerTarget.classList.contains("hidden")) {
            this.close();
          }
        }, 100);
      } else {
        console.error("Failed to update project");
      }
    } catch (error) {
      console.error("Error updating project:", error);
    }
  }

  positionOverlay() {
    const overlayWidth = 320; // w-80 = 20rem = 320px
    const overlayHeight = 400; // approximate
    let referenceElement = null;
    let rect = null;

    if (this.contextValue === "card") {
      // For card context, use the card we were opened for (shared picker) and
      // fall back to the legacy nested lookup.
      referenceElement = this.referenceCard || this.element.closest('[data-hovered="true"]');
      if (!referenceElement) return;
      rect = referenceElement.getBoundingClientRect();

      // Check if this is a wide element (like a list view row)
      const isWideElement = rect.width > 800;

      let top = rect.top;
      let left;

      if (isWideElement) {
        // For list view: center the picker horizontally on screen
        left = (window.innerWidth - overlayWidth) / 2;
      } else {
        // For board view: position to the left of the card
        left = rect.left - overlayWidth - 8; // 8px gap

        // If it would go off the left edge, position to the right instead
        if (left < 8) {
          left = rect.right + 8;
        }

        // If still off-screen to the right, center it
        if (left + overlayWidth > window.innerWidth - 8) {
          left = (window.innerWidth - overlayWidth) / 2;
        }
      }

      // Check if overlay would go off-screen vertically
      if (top + overlayHeight > window.innerHeight) {
        top = window.innerHeight - overlayHeight - 8;
      }
      if (top < 8) {
        top = 8;
      }

      this.pickerTarget.style.top = `${top}px`;
      this.pickerTarget.style.left = `${left}px`;
    } else {
      // For sidebar context, find the project dropdown button
      referenceElement = this.element.closest('[data-issue-sidebar-target="projectDropdown"]');
      if (!referenceElement) return;

      // Get the button that triggers the dropdown
      const button = referenceElement.previousElementSibling;
      if (button) {
        rect = button.getBoundingClientRect();
      } else {
        rect = referenceElement.getBoundingClientRect();
      }

      // Position to the left of the reference element
      let top = rect.top;
      let left = rect.left - overlayWidth - 8; // 8px gap

      // If it would go off the left edge, position to the right instead
      if (left < 8) {
        left = rect.right + 8;
      }

      // Check if overlay would go off-screen vertically
      if (top + overlayHeight > window.innerHeight) {
        top = window.innerHeight - overlayHeight - 8;
      }
      if (top < 8) {
        top = 8;
      }

      this.pickerTarget.style.top = `${top}px`;
      this.pickerTarget.style.left = `${left}px`;
    }
  }

  updateEmptyState(projectOptions) {
    const hasVisibleProjects = Array.from(projectOptions).some((el) => !el.classList.contains("hidden"));

    if (!hasVisibleProjects) {
      this.emptyStateTarget.classList.remove("hidden");
    } else {
      this.emptyStateTarget.classList.add("hidden");
    }
  }
}
