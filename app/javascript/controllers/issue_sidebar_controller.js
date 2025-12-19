import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "laneDropdown", "laneLabel", "laneInput",
    "priorityDropdown", "priorityLabel", "priorityInput",
    "assigneeDropdown", "assigneeLabel", "assigneeInput",
    "projectDropdown", "projectLabel", "projectInput",
    "estimateDropdown", "estimateLabel", "estimateInput"
  ]

  connect() {
    this.boundHandleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this.boundHandleClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.boundHandleClickOutside)
  }

  toggleDropdown(event) {
    event.stopPropagation()
    const dropdownType = event.currentTarget.dataset.dropdown
    const dropdownTarget = `${dropdownType}DropdownTarget`

    this.closeAllDropdowns()

    if (this[dropdownTarget]) {
      this[dropdownTarget].classList.toggle("hidden")
    }
  }

  closeAllDropdowns() {
    const dropdowns = ["laneDropdown", "priorityDropdown", "assigneeDropdown", "projectDropdown", "estimateDropdown"]

    dropdowns.forEach(dropdown => {
      try {
        const target = `${dropdown}Target`
        if (this[target]) {
          this[target].classList.add("hidden")
        }
      } catch (error) {
        // Target doesn't exist, skip
      }
    })
  }

  handleClickOutside(event) {
    if (!event.target.closest('[data-issue-sidebar-target*="Dropdown"]')) {
      this.closeAllDropdowns()
    }
  }

  selectLane(event) {
    event.stopPropagation()
    this.updateField(event, 'lane', 'laneInput', 'laneLabel', 'laneName')
    this.laneDropdownTarget.classList.add("hidden")
  }

  selectPriority(event) {
    event.stopPropagation()
    this.updateField(event, 'priority', 'priorityInput', 'priorityLabel', 'priorityLabel')
    this.priorityDropdownTarget.classList.add("hidden")
  }

  selectAssignee(event) {
    event.stopPropagation()
    this.updateField(event, 'assignee', 'assigneeInput', 'assigneeLabel', 'assigneeName')
    this.assigneeDropdownTarget.classList.add("hidden")
  }

  selectProject(event) {
    event.stopPropagation()
    this.updateField(event, 'project', 'projectInput', 'projectLabel', 'projectName')
    this.projectDropdownTarget.classList.add("hidden")
  }

  selectEstimate(event) {
    event.stopPropagation()
    this.updateField(event, 'estimate', 'estimateInput', 'estimateLabel', 'estimateLabel')
    this.estimateDropdownTarget.classList.add("hidden")
  }

  updateField(event, fieldType, inputTarget, labelTarget, dataAttribute) {
    const value = event.currentTarget.dataset[`${fieldType}Value`] ||
                  event.currentTarget.dataset[`${fieldType}Id`]
    const label = event.currentTarget.dataset[dataAttribute]

    // Access Stimulus targets with the Target suffix
    this[`${inputTarget}Target`].value = value
    this[`${labelTarget}Target`].textContent = label

    // Submit the form
    this.element.requestSubmit()
  }
}
