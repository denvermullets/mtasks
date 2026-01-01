import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = [
    "picker",
    "search",
    "laneList",
    "emptyState",
  ];

  static values = {
    issueId: Number,
    teamId: Number,
    context: String,
    currentLane: Number,
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

  filterLanes() {
    // Clear previous debounce timeout
    if (this.filterDebounceTimeout) {
      clearTimeout(this.filterDebounceTimeout);
    }

    // Debounce the filtering
    this.filterDebounceTimeout = setTimeout(() => {
      const query = this.searchTarget.value.trim().toLowerCase();
      const laneOptions = this.laneListTarget.querySelectorAll(".lane-option");

      if (query === "") {
        // Show all lanes
        laneOptions.forEach((el) => el.classList.remove("hidden"));
        this.updateEmptyState(laneOptions);
        return;
      }

      // Filter lanes
      let visibleCount = 0;

      laneOptions.forEach((el) => {
        const name = el.dataset.laneName.toLowerCase();
        if (name.includes(query)) {
          el.classList.remove("hidden");
          visibleCount++;
        } else {
          el.classList.add("hidden");
        }
      });

      this.updateEmptyState(laneOptions);
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
    return Array.from(this.laneListTarget.querySelectorAll(".lane-option:not(.hidden)"));
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

  async selectLane(event) {
    const laneOption = event.target.closest(".lane-option");
    const laneId = laneOption.dataset.laneId;

    await this.updateIssueLane(parseInt(laneId));
  }

  async updateIssueLane(laneId) {
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
            lane_id: laneId,
          },
        }),
      });

      if (response.ok) {
        this.currentLaneValue = laneId;

        // Get the turbo stream response and let Turbo handle it
        const turboStream = await response.text();
        Turbo.renderStreamMessage(turboStream);

        this.close();
      } else {
        console.error("Failed to update lane");
      }
    } catch (error) {
      console.error("Error updating lane:", error);
    }
  }

  positionOverlay() {
    const overlayWidth = 320; // w-80 = 20rem = 320px
    const overlayHeight = 400; // approximate
    let referenceElement = null;
    let rect = null;

    if (this.contextValue === "card") {
      // For card context, find the hovered card
      referenceElement = this.element.closest('[data-hovered="true"]');
      if (!referenceElement) return;
      rect = referenceElement.getBoundingClientRect();

      // Check if this is a wide element (like a list view row)
      // If the element is wider than 800px, it's probably a list row
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
      // For sidebar context, find the lane dropdown button
      referenceElement = this.element.closest('[data-issue-sidebar-target="laneDropdown"]');
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

  updateEmptyState(laneOptions) {
    const hasVisibleLanes = Array.from(laneOptions).some((el) => !el.classList.contains("hidden"));

    if (!hasVisibleLanes) {
      this.emptyStateTarget.classList.remove("hidden");
    } else {
      this.emptyStateTarget.classList.add("hidden");
    }
  }
}
