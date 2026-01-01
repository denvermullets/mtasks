import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["picker", "search", "milestoneList"];

  static values = {
    currentMilestone: Number,
  };

  connect() {
    this.currentFocusIndex = -1;

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

  filterMilestones() {
    // Clear previous debounce timeout
    if (this.filterDebounceTimeout) {
      clearTimeout(this.filterDebounceTimeout);
    }

    // Debounce the filtering
    this.filterDebounceTimeout = setTimeout(() => {
      const query = this.searchTarget.value.trim().toLowerCase();
      const milestoneOptions = this.milestoneListTarget.querySelectorAll(".milestone-option");

      if (query === "") {
        // Show all milestones
        milestoneOptions.forEach((el) => el.classList.remove("hidden"));
        return;
      }

      // Filter milestones
      milestoneOptions.forEach((el) => {
        const name = el.dataset.milestoneName.toLowerCase();
        if (name.includes(query)) {
          el.classList.remove("hidden");
        } else {
          el.classList.add("hidden");
        }
      });

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
    return Array.from(this.milestoneListTarget.querySelectorAll(".milestone-option:not(.hidden)"));
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

  selectMilestone(event) {
    const milestoneOption = event.target.closest(".milestone-option");
    const milestoneId = milestoneOption.dataset.milestoneId;
    const milestoneName = milestoneOption.dataset.milestoneName;
    const milestoneColor = milestoneOption.dataset.milestoneColor;

    // Update the form field
    const form = this.element.closest("form");
    const hiddenInput = form.querySelector('input[name="project[milestone_id]"]');
    const labelElement = form.querySelector('[data-project-form-target="milestoneLabel"]');
    const buttonElement = form.querySelector('[data-project-form-target="milestoneButton"]');

    if (hiddenInput) {
      hiddenInput.value = milestoneId;
    }

    // Update the button display
    if (buttonElement && milestoneId) {
      buttonElement.innerHTML = `
        <span style="color: ${milestoneColor};">◆</span>
        <span data-project-form-target="milestoneLabel">${milestoneName}</span>
      `;
    } else if (buttonElement) {
      buttonElement.innerHTML = `
        <span class="text-gray-500">◇</span>
        <span data-project-form-target="milestoneLabel" class="text-gray-500">No milestone</span>
      `;
    }

    this.close();
  }

  positionOverlay() {
    const overlayWidth = 320; // w-80 = 20rem = 320px
    const overlayHeight = 400; // approximate

    // Find the button that triggered this - search from the form element
    const form = this.element.closest("form");
    if (!form) return;

    const button = form.querySelector('[data-project-form-target="milestoneButton"]');
    if (!button) return;

    const rect = button.getBoundingClientRect();

    // Position to the left of the button
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
