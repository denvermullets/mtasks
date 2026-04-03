import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "statusDropdown",
    "statusLabel",
    "statusInput",
    "priorityDropdown",
    "priorityLabel",
    "priorityInput",
    "leadDropdown",
    "leadLabel",
    "leadInput",
    "labelsDropdown",
    "milestoneDropdown",
    "milestoneLabel",
    "milestoneInput",
    "startDateInput",
    "dueDateInput",
  ];

  connect() {
    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    document.addEventListener("click", this.boundHandleClickOutside);
  }

  disconnect() {
    document.removeEventListener("click", this.boundHandleClickOutside);
  }

  toggleDropdown(event) {
    event.stopPropagation();
    const dropdownType = event.currentTarget.dataset.dropdown;
    const dropdownTarget = `${dropdownType}DropdownTarget`;

    this.closeAllDropdowns();

    if (this[dropdownTarget]) {
      const wasHidden = this[dropdownTarget].classList.contains("hidden");
      this[dropdownTarget].classList.toggle("hidden");

      if (dropdownType === "labels" && wasHidden) {
        const labelPicker = this[dropdownTarget].querySelector(
          '[data-controller="label-picker"]'
        );
        if (labelPicker) {
          const controller = this.application.getControllerForElementAndIdentifier(
            labelPicker,
            "label-picker"
          );
          if (controller && controller.open) {
            controller.open();
          }
        }
      }

    }
  }

  closeAllDropdowns() {
    const dropdowns = [
      "statusDropdown",
      "priorityDropdown",
      "leadDropdown",
      "labelsDropdown",
      "milestoneDropdown",
    ];

    dropdowns.forEach((dropdown) => {
      try {
        const target = `${dropdown}Target`;
        if (this[target]) {
          this[target].classList.add("hidden");
        }
      } catch (error) {
        // Target doesn't exist, skip
      }
    });
  }

  handleClickOutside(event) {
    if (!event.target.closest('[data-project-sidebar-target*="Dropdown"]')) {
      this.closeAllDropdowns();
    }
  }

  selectStatus(event) {
    event.stopPropagation();
    const value = event.currentTarget.dataset.statusValue;
    const label = event.currentTarget.dataset.statusLabel;
    this.statusInputTarget.value = value;
    this.statusLabelTarget.textContent = label;
    this.statusDropdownTarget.classList.add("hidden");
    this.element.requestSubmit();
  }

  selectPriority(event) {
    event.stopPropagation();
    const value = event.currentTarget.dataset.priorityValue;
    const label = event.currentTarget.dataset.priorityLabel;
    this.priorityInputTarget.value = value;
    this.priorityLabelTarget.textContent = label;
    this.priorityDropdownTarget.classList.add("hidden");
    this.element.requestSubmit();
  }

  selectLead(event) {
    event.stopPropagation();
    const value = event.currentTarget.dataset.leadId;
    const label = event.currentTarget.dataset.leadName;
    this.leadInputTarget.value = value || "";
    this.leadLabelTarget.textContent = label;
    this.leadDropdownTarget.classList.add("hidden");
    this.element.requestSubmit();
  }

  selectMilestone(event) {
    event.stopPropagation();
    const value = event.currentTarget.dataset.milestoneId;
    const label = event.currentTarget.dataset.milestoneName;
    this.milestoneInputTarget.value = value || "";
    this.milestoneLabelTarget.textContent = label;
    this.milestoneDropdownTarget.classList.add("hidden");
    this.element.requestSubmit();
  }

  openDatePicker(event) {
    if (event.target.showPicker) {
      try {
        event.target.showPicker();
      } catch (e) {
        // showPicker may throw if already open
      }
    }
  }

  dateChanged() {
    this.element.requestSubmit();
  }
}
