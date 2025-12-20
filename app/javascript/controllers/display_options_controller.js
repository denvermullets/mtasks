import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.boundHandleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this.boundHandleClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.boundHandleClickOutside)
  }

  togglePanel(event) {
    event.stopPropagation()
    this.panelTarget.classList.toggle("hidden")
  }

  closePanel() {
    this.panelTarget.classList.add("hidden")
  }

  handleClickOutside(event) {
    // Check if click is outside the controller element
    if (!this.element.contains(event.target)) {
      this.closePanel()
    }
  }

  setViewMode(event) {
    const viewMode = event.currentTarget.dataset.viewMode

    // Build new URL with updated view_mode
    const url = new URL(window.location.href)
    url.searchParams.set('view_mode', viewMode)

    // Update browser URL without reload
    window.history.pushState({}, '', url.toString())

    // Update button states immediately
    this.updateViewModeButtons(viewMode)

    // Navigate with Turbo Frame to update only the board
    window.Turbo.visit(url.toString(), { frame: 'issues_board' })

    // Close the panel
    this.closePanel()
  }

  updateViewModeButtons(activeMode) {
    const buttons = this.element.querySelectorAll('[data-view-mode]')
    buttons.forEach(button => {
      const mode = button.dataset.viewMode
      if (mode === activeMode) {
        button.classList.add('bg-foreground', 'text-gray-100', 'border', 'border-stroke')
        button.classList.remove('text-gray-400', 'hover:text-gray-200')
      } else {
        button.classList.remove('bg-foreground', 'text-gray-100', 'border', 'border-stroke')
        button.classList.add('text-gray-400', 'hover:text-gray-200')
      }
    })
  }

  handleDropdownChange(event) {
    const param = event.currentTarget.dataset.param
    const value = event.currentTarget.value

    // Build new URL preserving all params
    const url = new URL(window.location.href)
    url.searchParams.set(param, value)

    // Navigate with Turbo Frame
    window.Turbo.visit(url.toString(), { frame: 'issues_board' })
  }

  toggleOption(event) {
    const param = event.currentTarget.dataset.param
    const checked = event.currentTarget.checked

    // Build new URL preserving all params
    const url = new URL(window.location.href)
    url.searchParams.set(param, checked)

    // Navigate with Turbo Frame
    window.Turbo.visit(url.toString(), { frame: 'issues_board' })
  }

  updateProperties(event) {
    // Get all checked properties
    const container = this.element.querySelector('[data-display-options-target="panel"]')
    const checkboxes = container.querySelectorAll('input[type="checkbox"]:checked')
    const properties = Array.from(checkboxes).map(cb => cb.value)

    // Build new URL preserving all params
    const url = new URL(window.location.href)
    if (properties.length > 0) {
      url.searchParams.set('visible_properties', properties.join(','))
    } else {
      url.searchParams.delete('visible_properties')
    }

    // Navigate with Turbo Frame (debounced)
    clearTimeout(this.propertiesTimeout)
    this.propertiesTimeout = setTimeout(() => {
      window.Turbo.visit(url.toString(), { frame: 'issues_board' })
    }, 300)
  }

  updateFormFromCurrentParams() {
    // Get current URL params
    const url = new URL(window.location.href)
    const params = url.searchParams

    // Update hidden form fields with current URL params
    const form = this.element.querySelector('form')
    if (!form) return

    // Update view_mode
    const viewModeInput = form.querySelector('input[name="view_mode"]')
    if (viewModeInput) {
      viewModeInput.value = params.get('view_mode') || 'board'
    }

    // Update group_by
    const groupByInput = form.querySelector('input[name="group_by"]')
    if (groupByInput) {
      groupByInput.value = params.get('group_by') || 'lane'
    }

    // Update order_by
    const orderByInput = form.querySelector('input[name="order_by"]')
    if (orderByInput) {
      orderByInput.value = params.get('order_by') || 'manual'
    }

    // Update show_sub_issues
    const showSubIssuesInput = form.querySelector('input[name="show_sub_issues"]')
    if (showSubIssuesInput) {
      showSubIssuesInput.value = params.get('show_sub_issues') || 'true'
    }

    // Update show_empty_groups
    const showEmptyGroupsInput = form.querySelector('input[name="show_empty_groups"]')
    if (showEmptyGroupsInput) {
      showEmptyGroupsInput.value = params.get('show_empty_groups') || 'false'
    }

    // Update completed_filter
    const completedFilterInput = form.querySelector('input[name="completed_filter"]')
    if (completedFilterInput) {
      completedFilterInput.value = params.get('completed_filter') || ''
    }

    // Update visible_properties - read from actual checkboxes in the panel, not URL
    // This ensures we save the current state even if user hasn't toggled them
    const existingPropertyInputs = form.querySelectorAll('input[name="visible_properties[]"]')
    existingPropertyInputs.forEach(input => input.remove())

    const container = this.element.querySelector('[data-display-options-target="panel"]')
    const checkedBoxes = container.querySelectorAll('input[type="checkbox"]:checked')
    const properties = Array.from(checkedBoxes).map(cb => cb.value)

    if (properties.length > 0) {
      const submitButton = form.querySelector('input[type="submit"]')
      properties.forEach(prop => {
        const input = document.createElement('input')
        input.type = 'hidden'
        input.name = 'visible_properties[]'
        input.value = prop
        form.insertBefore(input, submitButton)
      })
    }
  }

  savePreferences() {
    // Update form with current URL params before submission
    this.updateFormFromCurrentParams()
  }
}
