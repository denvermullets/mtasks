import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "laneDropdown", "laneLabel", "laneInput",
    "priorityDropdown", "priorityLabel", "priorityInput",
    "assigneeDropdown", "assigneeLabel", "assigneeInput",
    "projectDropdown", "projectLabel", "projectInput",
    "estimateDropdown", "estimateLabel", "estimateInput",
    "labelsLabel",
    "milestoneLabel"
  ]

  connect() {
    // Close dropdowns when clicking outside
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

    // Close all other dropdowns first
    this.closeAllDropdowns()

    // Toggle this dropdown
    if (this[dropdownTarget]) {
      this[dropdownTarget].classList.toggle("hidden")
    }
  }

  closeAllDropdowns() {
    const dropdowns = [
      "laneDropdown", "priorityDropdown", "assigneeDropdown",
      "projectDropdown", "estimateDropdown"
    ]

    dropdowns.forEach(dropdown => {
      try {
        const target = `${dropdown}Target`
        if (this[target]) {
          this[target].classList.add("hidden")
        }
      } catch (error) {
        // Target doesn't exist, skip it
      }
    })
  }

  handleClickOutside(event) {
    // If click is not inside any dropdown, close all
    if (!event.target.closest('[data-issue-form-target*="Dropdown"]')) {
      this.closeAllDropdowns()
    }
  }

  selectLane(event) {
    event.stopPropagation()
    const laneId = event.currentTarget.dataset.laneId
    const laneName = event.currentTarget.dataset.laneName

    this.laneInputTarget.value = laneId
    this.laneLabelTarget.textContent = laneName
    this.laneDropdownTarget.classList.add("hidden")
    this.triggerChange(this.laneInputTarget)
  }

  selectPriority(event) {
    event.stopPropagation()
    const priorityValue = event.currentTarget.dataset.priorityValue
    const priorityLabel = event.currentTarget.dataset.priorityLabel

    this.priorityInputTarget.value = priorityValue
    this.priorityLabelTarget.textContent = priorityLabel
    this.priorityDropdownTarget.classList.add("hidden")
    this.triggerChange(this.priorityInputTarget)
  }

  selectAssignee(event) {
    event.stopPropagation()
    const assigneeId = event.currentTarget.dataset.assigneeId
    const assigneeName = event.currentTarget.dataset.assigneeName

    this.assigneeInputTarget.value = assigneeId
    this.assigneeLabelTarget.textContent = assigneeName
    this.assigneeDropdownTarget.classList.add("hidden")
    this.triggerChange(this.assigneeInputTarget)
  }

  selectProject(event) {
    event.stopPropagation()
    const projectId = event.currentTarget.dataset.projectId
    const projectName = event.currentTarget.dataset.projectName

    this.projectInputTarget.value = projectId
    this.projectLabelTarget.textContent = projectName
    this.projectDropdownTarget.classList.add("hidden")
    this.triggerChange(this.projectInputTarget)
  }

  selectEstimate(event) {
    event.stopPropagation()
    const estimateValue = event.currentTarget.dataset.estimateValue
    const estimateLabel = event.currentTarget.dataset.estimateLabel

    this.estimateInputTarget.value = estimateValue
    this.estimateLabelTarget.textContent = estimateLabel
    this.estimateDropdownTarget.classList.add("hidden")
    this.triggerChange(this.estimateInputTarget)
  }

  triggerChange(element) {
    // Dispatch a change event to trigger any listeners
    element.dispatchEvent(new Event('change', { bubbles: true }))
  }

  submitForm() {
    // Auto-submit the form when a field changes
    this.element.requestSubmit()
  }

  updateLabelsCount(event) {
    // Don't close the labels dropdown when checking/unchecking
    event.stopPropagation()

    // Count checked labels
    const checkboxes = this.labelsDropdownTarget.querySelectorAll('input[type="checkbox"]:checked')
    const count = checkboxes.length

    if (count > 0) {
      this.labelsLabelTarget.textContent = `${count} label${count > 1 ? 's' : ''}`
    } else {
      this.labelsLabelTarget.textContent = "Labels"
    }
  }

  toggleLabelsDropdown(event) {
    event.stopPropagation()

    // Close all other dropdowns
    this.closeAllDropdowns()

    // Find and open the label picker
    const labelPickerElement = event.currentTarget.parentElement.querySelector('[data-controller="new-issue-label-picker"]')
    if (labelPickerElement) {
      const controller = this.application.getControllerForElementAndIdentifier(labelPickerElement, "new-issue-label-picker")
      if (controller && controller.open) {
        controller.open()
      }
    }
  }

  toggleMilestonesDropdown(event) {
    event.stopPropagation()

    // Close all other dropdowns
    this.closeAllDropdowns()

    // Find and open the milestone picker
    const milestonePickerElement = event.currentTarget.parentElement.querySelector('[data-controller="new-issue-milestone-picker"]')
    if (milestonePickerElement) {
      const controller = this.application.getControllerForElementAndIdentifier(milestonePickerElement, "new-issue-milestone-picker")
      if (controller && controller.open) {
        controller.open()
      }
    }
  }
}
