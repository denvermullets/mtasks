import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "statusDropdown", "statusLabel", "statusInput",
    "priorityDropdown", "priorityLabel", "priorityInput",
    "leadDropdown", "leadLabel", "leadInput",
    "labelsDropdown",
  ];

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
    if (event.target.matches("input, textarea")) {
      return;
    }

    if (event.key === "Escape") {
      this.closeAllDropdowns();
    }
  }

  handleClickOutside(event) {
    const dropdowns = ["statusDropdown", "priorityDropdown", "leadDropdown", "labelsDropdown"];
    dropdowns.forEach((dropdown) => {
      try {
        if (this[`${dropdown}Target`] && !this[`${dropdown}Target`].contains(event.target) &&
            !event.target.closest(`[data-dropdown="${dropdown.replace('Dropdown', '')}"]`)) {
          this[`${dropdown}Target`].classList.add("hidden");
        }
      } catch (e) {}
    });
  }

  toggleDropdown(event) {
    event.preventDefault();
    event.stopPropagation();
    const dropdownType = event.currentTarget.dataset.dropdown;
    const target = `${dropdownType}DropdownTarget`;

    this.closeAllDropdowns();

    if (this[target]) {
      this[target].classList.toggle("hidden");
    }
  }

  closeAllDropdowns() {
    ["statusDropdown", "priorityDropdown", "leadDropdown", "labelsDropdown"].forEach((dropdown) => {
      try {
        if (this[`${dropdown}Target`]) {
          this[`${dropdown}Target`].classList.add("hidden");
        }
      } catch (e) {}
    });
  }

  selectStatus(event) {
    event.stopPropagation();
    this.statusInputTarget.value = event.currentTarget.dataset.statusValue;
    this.statusLabelTarget.textContent = event.currentTarget.dataset.statusLabel;
    this.statusDropdownTarget.classList.add("hidden");
  }

  selectPriority(event) {
    event.stopPropagation();
    this.priorityInputTarget.value = event.currentTarget.dataset.priorityValue;
    this.priorityLabelTarget.textContent = event.currentTarget.dataset.priorityLabel;
    this.priorityDropdownTarget.classList.add("hidden");
  }

  selectLead(event) {
    event.stopPropagation();
    const leadId = event.currentTarget.dataset.leadId;
    this.leadInputTarget.value = leadId === "none" ? "" : leadId;
    this.leadLabelTarget.textContent = event.currentTarget.dataset.leadName;
    this.leadDropdownTarget.classList.add("hidden");
  }
}
