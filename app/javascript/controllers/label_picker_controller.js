import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "picker", "search", "labelList", "createOption", "createButton", "createText",
    "frequentlyUsedSection", "frequentlyUsedList", "allLabelsList", "allLabelsHeader",
    "emptyState", "loadingState"
  ]

  static values = {
    issueId: Number,
    teamId: Number,
    context: String,
    currentLabels: Array
  }

  connect() {
    this.currentFocusIndex = -1
    this.allLabels = []
    this.frequentlyUsedLabels = []
    this.filteredLabels = []
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    // Bind event handlers
    this.boundHandleClickOutside = this.handleClickOutside.bind(this)
    this.boundHandleEscape = this.handleEscape.bind(this)

    // Set up debounced filter
    this.filterDebounceTimeout = null
  }

  disconnect() {
    this.close()
  }

  async open() {
    // Load labels data
    await this.loadLabels()

    // Show picker
    this.pickerTarget.classList.remove("hidden")

    // Position overlay (for both card and sidebar contexts)
    this.positionOverlay()

    // Focus search input
    this.searchTarget.focus()

    // Add event listeners
    document.addEventListener("click", this.boundHandleClickOutside)
    document.addEventListener("keydown", this.boundHandleEscape)
  }

  close() {
    this.pickerTarget.classList.add("hidden")
    this.searchTarget.value = ""
    this.currentFocusIndex = -1

    // Remove event listeners
    document.removeEventListener("click", this.boundHandleClickOutside)
    document.removeEventListener("keydown", this.boundHandleEscape)
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  handleEscape(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  async loadLabels() {
    this.showLoading()

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/labels`, {
        headers: {
          "Accept": "application/json"
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.allLabels = data.all_labels
        this.frequentlyUsedLabels = data.frequently_used
        this.renderLabels()
      }
    } catch (error) {
      console.error("Failed to load labels:", error)
      this.showError()
    } finally {
      this.hideLoading()
    }
  }

  renderLabels() {
    // Render frequently used section
    if (this.frequentlyUsedLabels.length > 0) {
      this.frequentlyUsedSectionTarget.classList.remove("hidden")
      this.frequentlyUsedListTarget.innerHTML = ""
      this.frequentlyUsedLabels.forEach(label => {
        this.frequentlyUsedListTarget.appendChild(this.createLabelElement(label))
      })
    } else {
      this.frequentlyUsedSectionTarget.classList.add("hidden")
    }

    // Render all labels
    this.allLabelsListTarget.innerHTML = ""
    this.allLabels.forEach(label => {
      this.allLabelsListTarget.appendChild(this.createLabelElement(label))
    })

    this.filteredLabels = Array.from(this.labelListTarget.querySelectorAll(".label-option"))
    this.updateEmptyState()
  }

  createLabelElement(label) {
    const div = document.createElement("label")
    div.className = "label-option flex items-center px-3 py-2 text-sm text-gray-300 hover:bg-hover-highlight transition-colors cursor-pointer"
    div.dataset.labelId = label.id
    div.dataset.labelName = label.name
    div.dataset.labelColor = label.color
    div.setAttribute("role", "option")

    const isChecked = this.currentLabelsValue.includes(label.id)

    div.innerHTML = `
      <input type="checkbox"
             ${isChecked ? "checked" : ""}
             class="mr-2 rounded bg-background border-stroke accent-accent focus:ring-0 focus:ring-offset-0"
             data-action="change->label-picker#toggleLabel" />
      <span class="w-3 h-3 rounded-full mr-2 flex-shrink-0" style="background-color: ${label.color};"></span>
      <span class="flex-1 truncate">${label.name}</span>
    `

    return div
  }

  filterLabels() {
    // Clear previous debounce timeout
    if (this.filterDebounceTimeout) {
      clearTimeout(this.filterDebounceTimeout)
    }

    // Debounce the filtering
    this.filterDebounceTimeout = setTimeout(() => {
      const query = this.searchTarget.value.trim().toLowerCase()

      if (query === "") {
        // Show all labels
        this.filteredLabels.forEach(el => el.classList.remove("hidden"))
        this.createOptionTarget.classList.add("hidden")
        this.updateEmptyState()
        return
      }

      // Filter labels
      let visibleCount = 0
      let exactMatch = false

      this.filteredLabels.forEach(el => {
        const name = el.dataset.labelName.toLowerCase()
        if (name.includes(query)) {
          el.classList.remove("hidden")
          visibleCount++
          if (name === query) {
            exactMatch = true
          }
        } else {
          el.classList.add("hidden")
        }
      })

      // Show create option if no exact match
      if (!exactMatch && query.length > 0) {
        this.createTextTarget.textContent = query
        this.createOptionTarget.classList.remove("hidden")
      } else {
        this.createOptionTarget.classList.add("hidden")
      }

      this.updateEmptyState()
      this.currentFocusIndex = -1
    }, 300)
  }

  handleKeyDown(event) {
    // Don't interfere with normal typing
    if (!["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) {
      return
    }

    event.preventDefault()

    switch(event.key) {
      case "ArrowDown":
        this.focusNext()
        break
      case "ArrowUp":
        this.focusPrevious()
        break
      case "Enter":
        this.selectFocused()
        break
      case "Escape":
        this.close()
        break
    }
  }

  focusNext() {
    const visibleOptions = this.getVisibleOptions()
    if (visibleOptions.length === 0) return

    this.currentFocusIndex++
    if (this.currentFocusIndex >= visibleOptions.length) {
      this.currentFocusIndex = 0
    }

    this.updateVisualFocus(visibleOptions)
  }

  focusPrevious() {
    const visibleOptions = this.getVisibleOptions()
    if (visibleOptions.length === 0) return

    this.currentFocusIndex--
    if (this.currentFocusIndex < 0) {
      this.currentFocusIndex = visibleOptions.length - 1
    }

    this.updateVisualFocus(visibleOptions)
  }

  getVisibleOptions() {
    const options = []

    // Include create option if visible
    if (!this.createOptionTarget.classList.contains("hidden")) {
      options.push({ type: "create", element: this.createButtonTarget })
    }

    // Include visible label options
    this.filteredLabels.forEach(el => {
      if (!el.classList.contains("hidden")) {
        options.push({ type: "label", element: el })
      }
    })

    return options
  }

  updateVisualFocus(visibleOptions) {
    // Remove focus from all
    visibleOptions.forEach(option => {
      option.element.classList.remove("bg-hover-highlight")
    })

    // Add focus to current
    if (this.currentFocusIndex >= 0 && this.currentFocusIndex < visibleOptions.length) {
      const focused = visibleOptions[this.currentFocusIndex]
      focused.element.classList.add("bg-hover-highlight")
      focused.element.scrollIntoView({ block: "nearest" })
    }
  }

  selectFocused() {
    const visibleOptions = this.getVisibleOptions()
    if (this.currentFocusIndex < 0 || this.currentFocusIndex >= visibleOptions.length) return

    const focused = visibleOptions[this.currentFocusIndex]

    if (focused.type === "create") {
      this.createAndToggleLabel()
    } else {
      const checkbox = focused.element.querySelector("input[type=checkbox]")
      checkbox.checked = !checkbox.checked
      this.toggleLabel({ target: checkbox })
    }
  }

  async toggleLabel(event) {
    const checkbox = event.target
    const labelOption = checkbox.closest(".label-option")
    const labelId = parseInt(labelOption.dataset.labelId)
    const isChecked = checkbox.checked

    try {
      if (isChecked) {
        await this.addLabelToIssue(labelId)
      } else {
        await this.removeLabelFromIssue(labelId)
      }
    } catch (error) {
      // Revert checkbox on error
      checkbox.checked = !isChecked
      console.error("Failed to toggle label:", error)
    }
  }

  async addLabelToIssue(labelId) {
    const response = await fetch(`/teams/${this.teamIdValue}/issues/${this.issueIdValue}/issue_labels`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify({ label_id: labelId })
    })

    if (!response.ok) {
      throw new Error("Failed to add label")
    }

    // Update current labels
    this.currentLabelsValue = [...this.currentLabelsValue, labelId]

    // Dispatch event to update card display
    window.dispatchEvent(new CustomEvent("label-picker:labelAdded", {
      detail: { labelId, issueId: this.issueIdValue },
      bubbles: true
    }))
  }

  async removeLabelFromIssue(labelId) {
    const response = await fetch(`/teams/${this.teamIdValue}/issues/${this.issueIdValue}/issue_labels/${labelId}`, {
      method: "DELETE",
      headers: {
        "X-CSRF-Token": this.csrfToken
      }
    })

    if (!response.ok) {
      throw new Error("Failed to remove label")
    }

    // Update current labels
    this.currentLabelsValue = this.currentLabelsValue.filter(id => id !== labelId)

    // Dispatch event to update card display
    window.dispatchEvent(new CustomEvent("label-picker:labelRemoved", {
      detail: { labelId, issueId: this.issueIdValue },
      bubbles: true
    }))
  }

  async createAndToggleLabel() {
    const name = this.searchTarget.value.trim()
    if (!name) return

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/labels`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          label: {
            name: name,
            color: this.randomColor()
          }
        })
      })

      if (response.ok) {
        const label = await response.json()

        // Add to labels array
        this.allLabels.push({
          id: label.id,
          name: label.name,
          color: label.color,
          usage_count: 0
        })

        // Re-render to include new label
        this.renderLabels()

        // Automatically add to issue
        await this.addLabelToIssue(label.id)

        // Check the new label's checkbox
        const newLabelElement = this.labelListTarget.querySelector(`[data-label-id="${label.id}"]`)
        if (newLabelElement) {
          const checkbox = newLabelElement.querySelector("input[type=checkbox]")
          checkbox.checked = true
        }

        // Clear search
        this.searchTarget.value = ""
        this.filterLabels()

      } else {
        const error = await response.json()
        console.error("Failed to create label:", error)
      }
    } catch (error) {
      console.error("Failed to create label:", error)
    }
  }

  randomColor() {
    const colors = ['#ef4444', '#f59e0b', '#10b981', '#3b82f6', '#8b5cf6', '#ec4899']
    return colors[Math.floor(Math.random() * colors.length)]
  }

  positionOverlay() {
    const overlayWidth = 320 // w-80 = 20rem = 320px
    const overlayHeight = 400 // approximate
    let referenceElement = null
    let rect = null

    if (this.contextValue === "card") {
      // For card context, find the hovered card
      referenceElement = this.element.closest('[data-hovered="true"]')
      if (!referenceElement) return
      rect = referenceElement.getBoundingClientRect()
    } else {
      // For sidebar context, find the labels dropdown button
      referenceElement = this.element.closest('[data-issue-sidebar-target="labelsDropdown"]')
      if (!referenceElement) return

      // Get the button that triggers the dropdown
      const button = referenceElement.previousElementSibling
      if (button) {
        rect = button.getBoundingClientRect()
      } else {
        rect = referenceElement.getBoundingClientRect()
      }
    }

    // Position to the left of the reference element
    let top = rect.top
    let left = rect.left - overlayWidth - 8 // 8px gap

    // If it would go off the left edge, position to the right instead
    if (left < 8) {
      left = rect.right + 8
    }

    // Check if overlay would go off-screen vertically
    if (top + overlayHeight > window.innerHeight) {
      top = window.innerHeight - overlayHeight - 8
    }
    if (top < 8) {
      top = 8
    }

    this.pickerTarget.style.top = `${top}px`
    this.pickerTarget.style.left = `${left}px`
  }

  showLoading() {
    this.loadingStateTarget.classList.remove("hidden")
    this.emptyStateTarget.classList.add("hidden")
  }

  hideLoading() {
    this.loadingStateTarget.classList.add("hidden")
  }

  showError() {
    // Could show error message here
    this.hideLoading()
  }

  updateEmptyState() {
    const hasVisibleLabels = this.filteredLabels.some(el => !el.classList.contains("hidden"))
    const createVisible = !this.createOptionTarget.classList.contains("hidden")

    if (!hasVisibleLabels && !createVisible) {
      this.emptyStateTarget.classList.remove("hidden")
    } else {
      this.emptyStateTarget.classList.add("hidden")
    }
  }
}
