import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "picker", "search", "labelList", "createOption", "createButton", "createText",
    "allLabelsList", "emptyState", "loadingState", "selectedLabels"
  ]

  static values = {
    teamId: Number,
    selectedLabelIds: Array
  }

  connect() {
    this.allLabels = []
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    // Bind event handlers
    this.boundHandleClickOutside = this.handleClickOutside.bind(this)
    this.boundHandleEscape = this.handleEscape.bind(this)

    // Initialize selected label IDs from value
    if (!this.selectedLabelIdsValue) {
      this.selectedLabelIdsValue = []
    }
  }

  disconnect() {
    this.close()
  }

  async open() {
    // Load labels data
    await this.loadLabels()

    // Show picker
    this.pickerTarget.classList.remove("hidden")

    // Position overlay
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
        this.renderLabels()
      }
    } catch (error) {
      console.error("Failed to load labels:", error)
    } finally {
      this.hideLoading()
    }
  }

  renderLabels() {
    // Render all labels
    this.allLabelsListTarget.innerHTML = ""
    this.allLabels.forEach(label => {
      this.allLabelsListTarget.appendChild(this.createLabelElement(label))
    })

    this.updateEmptyState()
  }

  createLabelElement(label) {
    const div = document.createElement("label")
    div.className = "label-option flex items-center px-3 py-2 text-sm text-gray-300 hover:bg-hover-highlight transition-colors cursor-pointer"
    div.dataset.labelId = label.id
    div.dataset.labelName = label.name
    div.dataset.labelColor = label.color

    const isChecked = this.selectedLabelIdsValue.includes(label.id)

    div.innerHTML = `
      <input type="checkbox"
             ${isChecked ? "checked" : ""}
             class="mr-2 rounded bg-background border-stroke accent-accent focus:ring-0 focus:ring-offset-0"
             data-action="change->new-issue-label-picker#toggleLabel" />
      <span class="w-3 h-3 rounded-full mr-2 flex-shrink-0" style="background-color: ${label.color};"></span>
      <span class="flex-1 truncate">${label.name}</span>
    `

    return div
  }

  filterLabels() {
    const query = this.searchTarget.value.trim().toLowerCase()
    const labelOptions = this.labelListTarget.querySelectorAll(".label-option")

    if (query === "") {
      // Show all labels
      labelOptions.forEach(el => el.classList.remove("hidden"))
      this.createOptionTarget.classList.add("hidden")
      this.updateEmptyState()
      return
    }

    // Filter labels
    let visibleCount = 0
    let exactMatch = false

    labelOptions.forEach(el => {
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
  }

  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  toggleLabel(event) {
    const checkbox = event.target
    const labelOption = checkbox.closest(".label-option")
    const labelId = parseInt(labelOption.dataset.labelId)
    const isChecked = checkbox.checked

    if (isChecked) {
      // Add to selected labels
      if (!this.selectedLabelIdsValue.includes(labelId)) {
        this.selectedLabelIdsValue = [...this.selectedLabelIdsValue, labelId]
      }
    } else {
      // Remove from selected labels
      this.selectedLabelIdsValue = this.selectedLabelIdsValue.filter(id => id !== labelId)
    }

    this.updateHiddenFields()
    this.updateSelectedLabelsDisplay()
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
          color: label.color
        })

        // Re-render to include new label
        this.renderLabels()

        // Automatically select the new label
        this.selectedLabelIdsValue = [...this.selectedLabelIdsValue, label.id]

        // Check the new label's checkbox
        const newLabelElement = this.labelListTarget.querySelector(`[data-label-id="${label.id}"]`)
        if (newLabelElement) {
          const checkbox = newLabelElement.querySelector("input[type=checkbox]")
          checkbox.checked = true
        }

        // Update hidden fields and display
        this.updateHiddenFields()
        this.updateSelectedLabelsDisplay()

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

  updateHiddenFields() {
    // Find the container for hidden fields
    const container = this.element.querySelector('[data-new-issue-label-picker-target="hiddenFields"]')
    if (!container) return

    // Clear existing hidden fields
    container.innerHTML = ""

    // Add hidden field for each selected label
    this.selectedLabelIdsValue.forEach(labelId => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "issue[label_ids][]"
      input.value = labelId
      container.appendChild(input)
    })
  }

  updateSelectedLabelsDisplay() {
    // Update the button label to show count
    const button = this.element.closest('.relative').querySelector('button')
    if (!button) return

    const labelSpan = button.querySelector('[data-issue-form-target="labelsLabel"]')
    if (!labelSpan) return

    const count = this.selectedLabelIdsValue.length
    if (count > 0) {
      labelSpan.textContent = `${count} label${count > 1 ? 's' : ''}`
    } else {
      labelSpan.textContent = "Labels"
    }
  }

  randomColor() {
    const colors = ['#ef4444', '#f59e0b', '#10b981', '#3b82f6', '#8b5cf6', '#ec4899']
    return colors[Math.floor(Math.random() * colors.length)]
  }

  positionOverlay() {
    // Get the button that triggered this
    const button = this.element.closest('.relative').querySelector('button')
    if (!button) return

    const rect = button.getBoundingClientRect()
    const overlayWidth = 320 // w-80

    // Position below the button
    let top = rect.bottom + 4
    let left = rect.left

    // Check if overlay would go off-screen horizontally
    if (left + overlayWidth > window.innerWidth) {
      left = window.innerWidth - overlayWidth - 8
    }
    if (left < 8) {
      left = 8
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

  updateEmptyState() {
    const labelOptions = this.labelListTarget.querySelectorAll(".label-option")
    const hasVisibleLabels = Array.from(labelOptions).some(el => !el.classList.contains("hidden"))
    const createVisible = !this.createOptionTarget.classList.contains("hidden")

    if (!hasVisibleLabels && !createVisible) {
      this.emptyStateTarget.classList.remove("hidden")
    } else {
      this.emptyStateTarget.classList.add("hidden")
    }
  }
}
