import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["milestoneButton", "milestoneLabel", "milestoneInput", "milestoneDropdown"];

  connect() {
    this.boundHandleKeyDown = this.handleKeyDown.bind(this);
    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    document.addEventListener("keydown", this.boundHandleKeyDown);
    document.addEventListener("click", this.boundHandleClickOutside);
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeyDown);
    document.removeEventListener("click", this.boundHandleClickOutside);
  }

  handleKeyDown(event) {
    // Ignore if user is typing in an input or textarea
    if (event.target.matches("input, textarea")) {
      return;
    }

    // Open milestone dropdown with 'M' key
    if (event.key === "m" || event.key === "M") {
      event.preventDefault();
      this.openMilestoneDropdown();
    }

    // Close dropdown with Escape
    if (event.key === "Escape") {
      this.closeMilestoneDropdown();
    }
  }

  handleClickOutside(event) {
    if (this.hasMilestoneDropdownTarget &&
        !this.milestoneDropdownTarget.contains(event.target) &&
        !this.milestoneButtonTarget.contains(event.target)) {
      this.closeMilestoneDropdown();
    }
  }

  toggleMilestonePicker(event) {
    event.preventDefault();
    event.stopPropagation();

    // Find the milestone picker and toggle it
    const milestonePicker = this.milestoneDropdownTarget.querySelector('[data-controller="milestone-form-picker"]');
    if (!milestonePicker) return;

    const controller = this.application.getControllerForElementAndIdentifier(
      milestonePicker,
      "milestone-form-picker"
    );

    if (controller) {
      // Check if picker is currently visible
      const isHidden = controller.pickerTarget.classList.contains("hidden");
      if (isHidden) {
        controller.open();
      } else {
        controller.close();
      }
    }
  }

  openMilestoneDropdown() {
    const milestonePicker = this.milestoneDropdownTarget.querySelector('[data-controller="milestone-form-picker"]');
    if (!milestonePicker) return;

    const controller = this.application.getControllerForElementAndIdentifier(
      milestonePicker,
      "milestone-form-picker"
    );
    if (controller && controller.open) {
      controller.open();
    }
  }

  closeMilestoneDropdown() {
    const milestonePicker = this.milestoneDropdownTarget.querySelector('[data-controller="milestone-form-picker"]');
    if (!milestonePicker) return;

    const controller = this.application.getControllerForElementAndIdentifier(
      milestonePicker,
      "milestone-form-picker"
    );
    if (controller && controller.close) {
      controller.close();
    }
  }
}
