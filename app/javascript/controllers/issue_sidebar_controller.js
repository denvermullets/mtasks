import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "laneDropdown", "laneLabel", "laneInput",
    "priorityDropdown", "priorityLabel", "priorityInput",
    "assigneeDropdown", "assigneeLabel", "assigneeInput",
    "projectDropdown", "projectLabel", "projectInput",
    "estimateDropdown", "estimateLabel", "estimateInput",
    "labelsDropdown"
  ]

  connect() {
    this.boundHandleClickOutside = this.handleClickOutside.bind(this)
    this.boundHandleKeyDown = this.handleKeyDown.bind(this)
    document.addEventListener("click", this.boundHandleClickOutside)
    document.addEventListener("keydown", this.boundHandleKeyDown)
  }

  disconnect() {
    document.removeEventListener("click", this.boundHandleClickOutside)
    document.removeEventListener("keydown", this.boundHandleKeyDown)
  }

  toggleDropdown(event) {
    event.stopPropagation()
    const dropdownType = event.currentTarget.dataset.dropdown
    const dropdownTarget = `${dropdownType}DropdownTarget`

    this.closeAllDropdowns()

    if (this[dropdownTarget]) {
      const wasHidden = this[dropdownTarget].classList.contains("hidden")
      this[dropdownTarget].classList.toggle("hidden")

      // If this is the labels dropdown and we're opening it, also open the label picker
      if (dropdownType === "labels" && wasHidden) {
        const labelPicker = this[dropdownTarget].querySelector('[data-controller="label-picker"]')
        if (labelPicker) {
          const controller = this.application.getControllerForElementAndIdentifier(labelPicker, "label-picker")
          if (controller && controller.open) {
            controller.open()
          }
        }
      }
    }
  }

  closeAllDropdowns() {
    const dropdowns = ["laneDropdown", "priorityDropdown", "assigneeDropdown", "projectDropdown", "estimateDropdown", "labelsDropdown"]

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

  handleKeyDown(event) {
    // Ignore if user is typing in an input or textarea
    if (event.target.matches('input, textarea')) {
      return
    }

    // Open labels dropdown with 'L' key
    if (event.key === 'l' || event.key === 'L') {
      event.preventDefault()
      this.closeAllDropdowns()
      if (this.hasLabelsDropdownTarget) {
        this.labelsDropdownTarget.classList.remove("hidden")
        // Find and open the label picker
        const labelPicker = this.labelsDropdownTarget.querySelector('[data-controller="label-picker"]')
        if (labelPicker) {
          const controller = this.application.getControllerForElementAndIdentifier(labelPicker, "label-picker")
          if (controller && controller.open) {
            controller.open()
          }
        }
      }
    }
  }

  handleLabelChange() {
    // Refresh the page to show updated labels
    if (typeof Turbo !== 'undefined') {
      Turbo.visit(window.location.href, { action: 'replace' })
    } else {
      window.location.reload()
    }
  }
}
