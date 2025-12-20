import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "saveButton", "rowsSection", "groupingLabel", "groupingIcon"]

  connect() {
    this.boundHandleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this.boundHandleClickOutside)

    // Store initial saved preferences from the form
    this.savedPreferences = this.getCurrentFormValues()

    // Check initial state
    this.checkIfChanged()
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

    // Update visible options based on view mode
    this.updateOptionsForViewMode(viewMode)

    // Navigate with Turbo Frame to update only the board
    window.Turbo.visit(url.toString(), { frame: 'issues_board' })

    // Check if preferences have changed
    this.checkIfChanged()
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

  updateOptionsForViewMode(viewMode) {
    // Update grouping label
    if (this.hasGroupingLabelTarget) {
      this.groupingLabelTarget.textContent = viewMode === 'board' ? 'Columns' : 'Grouping'
    }

    // Update grouping icon
    if (this.hasGroupingIconTarget) {
      const icon = this.groupingIconTarget
      if (viewMode === 'board') {
        // Columns icon
        icon.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 4H5a2 2 0 00-2 2v4m6-6h6m-6 0v6m6-6v6m6-6a2 2 0 012 2v4M4 10v6a2 2 0 002 2h4m-6-8h6m0 8v6m0-6h6m0 6v6m0-6a2 2 0 012-2h4"></path>'
      } else {
        // List/rows icon
        icon.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16"></path>'
      }
    }

    // Show/hide rows section
    if (this.hasRowsSectionTarget) {
      if (viewMode === 'board') {
        this.rowsSectionTarget.classList.remove('hidden')
      } else {
        this.rowsSectionTarget.classList.add('hidden')
      }
    }
  }

  handleDropdownChange(event) {
    const param = event.currentTarget.dataset.param
    const value = event.currentTarget.value

    // Build new URL preserving all params
    const url = new URL(window.location.href)
    url.searchParams.set(param, value)

    // Update browser URL
    window.history.pushState({}, '', url.toString())

    // Navigate with Turbo Frame
    window.Turbo.visit(url.toString(), { frame: 'issues_board' })

    // Check if preferences have changed
    this.checkIfChanged()
  }

  toggleOption(event) {
    const param = event.currentTarget.dataset.param
    const checked = event.currentTarget.checked

    // Build new URL preserving all params
    const url = new URL(window.location.href)
    url.searchParams.set(param, checked)

    // Update browser URL
    window.history.pushState({}, '', url.toString())

    // Navigate with Turbo Frame
    window.Turbo.visit(url.toString(), { frame: 'issues_board' })

    // Check if preferences have changed
    this.checkIfChanged()
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

    // Update browser URL
    window.history.pushState({}, '', url.toString())

    // Navigate with Turbo Frame (debounced)
    clearTimeout(this.propertiesTimeout)
    this.propertiesTimeout = setTimeout(() => {
      window.Turbo.visit(url.toString(), { frame: 'issues_board' })
      // Check if preferences have changed
      this.checkIfChanged()
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
      groupByInput.value = params.get('group_by') || 'none'
    }

    // Update sub_group_by
    const subGroupByInput = form.querySelector('input[name="sub_group_by"]')
    if (subGroupByInput) {
      subGroupByInput.value = params.get('sub_group_by') || 'none'
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

    // Update show_empty_rows
    const showEmptyRowsInput = form.querySelector('input[name="show_empty_rows"]')
    if (showEmptyRowsInput) {
      showEmptyRowsInput.value = params.get('show_empty_rows') || 'false'
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

  getCurrentFormValues() {
    const form = this.element.querySelector('form')
    if (!form) return {}

    const container = this.element.querySelector('[data-display-options-target="panel"]')
    const checkedBoxes = container.querySelectorAll('input[type="checkbox"]:checked')
    const properties = Array.from(checkedBoxes).map(cb => cb.value).sort().join(',')

    return {
      view_mode: form.querySelector('input[name="view_mode"]')?.value || 'board',
      group_by: form.querySelector('input[name="group_by"]')?.value || 'none',
      sub_group_by: form.querySelector('input[name="sub_group_by"]')?.value || 'none',
      order_by: form.querySelector('input[name="order_by"]')?.value || 'manual',
      show_sub_issues: form.querySelector('input[name="show_sub_issues"]')?.value || 'true',
      show_empty_groups: form.querySelector('input[name="show_empty_groups"]')?.value || 'false',
      show_empty_rows: form.querySelector('input[name="show_empty_rows"]')?.value || 'false',
      completed_filter: form.querySelector('input[name="completed_filter"]')?.value || '',
      visible_properties: properties
    }
  }

  getCurrentUrlValues() {
    const url = new URL(window.location.href)
    const params = url.searchParams

    const container = this.element.querySelector('[data-display-options-target="panel"]')
    const checkedBoxes = container.querySelectorAll('input[type="checkbox"]:checked')
    const properties = Array.from(checkedBoxes).map(cb => cb.value).sort().join(',')

    return {
      view_mode: params.get('view_mode') || 'board',
      group_by: params.get('group_by') || 'none',
      sub_group_by: params.get('sub_group_by') || 'none',
      order_by: params.get('order_by') || 'manual',
      show_sub_issues: params.get('show_sub_issues') || 'true',
      show_empty_groups: params.get('show_empty_groups') || 'false',
      show_empty_rows: params.get('show_empty_rows') || 'false',
      completed_filter: params.get('completed_filter') || '',
      visible_properties: properties
    }
  }

  checkIfChanged() {
    if (!this.hasSaveButtonTarget) return

    const current = this.getCurrentUrlValues()
    const saved = this.savedPreferences

    const hasChanged =
      current.view_mode !== saved.view_mode ||
      current.group_by !== saved.group_by ||
      current.sub_group_by !== saved.sub_group_by ||
      current.order_by !== saved.order_by ||
      current.show_sub_issues !== saved.show_sub_issues ||
      current.show_empty_groups !== saved.show_empty_groups ||
      current.show_empty_rows !== saved.show_empty_rows ||
      current.completed_filter !== saved.completed_filter ||
      current.visible_properties !== saved.visible_properties

    this.saveButtonTarget.disabled = !hasChanged

    if (hasChanged) {
      this.saveButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      this.saveButtonTarget.classList.add('cursor-pointer')
    } else {
      this.saveButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      this.saveButtonTarget.classList.remove('cursor-pointer')
    }
  }
}
