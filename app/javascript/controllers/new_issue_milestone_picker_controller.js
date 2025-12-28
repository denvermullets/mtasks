import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "picker", "search", "milestoneList", "createOption", "createButton", "createText",
    "allMilestonesList", "emptyState", "loadingState", "hiddenField"
  ]

  static values = {
    teamId: Number,
    selectedMilestoneId: Number
  }

  connect() {
    this.allMilestones = []
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    // Bind event handlers
    this.boundHandleClickOutside = this.handleClickOutside.bind(this)
    this.boundHandleEscape = this.handleEscape.bind(this)
  }

  disconnect() {
    this.close()
  }

  async open() {
    // Load milestones data
    await this.loadMilestones()

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

  async loadMilestones() {
    this.showLoading()

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/milestones`, {
        headers: {
          "Accept": "application/json"
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.allMilestones = data.milestones
        this.renderMilestones()
      }
    } catch (error) {
      console.error("Failed to load milestones:", error)
    } finally {
      this.hideLoading()
    }
  }

  renderMilestones() {
    // Clear list
    this.allMilestonesListTarget.innerHTML = ""

    // Add "No milestone" option first
    this.allMilestonesListTarget.appendChild(this.createNoMilestoneElement())

    // Add divider
    const divider = document.createElement("div")
    divider.className = "border-t border-stroke my-1"
    this.allMilestonesListTarget.appendChild(divider)

    // Add all milestones
    this.allMilestones.forEach(milestone => {
      this.allMilestonesListTarget.appendChild(this.createMilestoneElement(milestone))
    })

    this.updateEmptyState()
  }

  createNoMilestoneElement() {
    const label = document.createElement("label")
    label.className = "milestone-option flex items-center px-3 py-2 text-sm text-gray-500 hover:bg-hover-highlight transition-colors cursor-pointer"
    label.dataset.milestoneId = ""
    label.dataset.milestoneName = "No milestone"

    const isSelected = !this.selectedMilestoneIdValue

    label.innerHTML = `
      <input type="radio"
             name="milestone-picker"
             ${isSelected ? "checked" : ""}
             class="mr-2 rounded-full bg-background border-stroke accent-accent focus:ring-0 focus:ring-offset-0"
             data-action="change->new-issue-milestone-picker#selectMilestone" />
      <span class="text-gray-500 mr-2">◇</span>
      <span class="flex-1">No milestone</span>
    `

    return label
  }

  createMilestoneElement(milestone) {
    const label = document.createElement("label")
    label.className = "milestone-option flex items-center px-3 py-2 text-sm text-gray-300 hover:bg-hover-highlight transition-colors cursor-pointer"
    label.dataset.milestoneId = milestone.id
    label.dataset.milestoneName = milestone.name

    const isSelected = this.selectedMilestoneIdValue === milestone.id

    label.innerHTML = `
      <input type="radio"
             name="milestone-picker"
             ${isSelected ? "checked" : ""}
             class="mr-2 rounded-full bg-background border-stroke accent-accent focus:ring-0 focus:ring-offset-0"
             data-action="change->new-issue-milestone-picker#selectMilestone" />
      <span style="color: ${milestone.status_color};" class="mr-2">◆</span>
      <span class="flex-1 truncate">${milestone.name}</span>
      ${milestone.formatted_due_date ? `<span class="text-xs text-gray-500">• ${milestone.formatted_due_date}</span>` : ''}
    `

    return label
  }

  filterMilestones() {
    const query = this.searchTarget.value.trim().toLowerCase()
    const milestoneOptions = this.milestoneListTarget.querySelectorAll(".milestone-option")

    if (query === "") {
      // Show all milestones
      milestoneOptions.forEach(el => el.classList.remove("hidden"))
      this.createOptionTarget.classList.add("hidden")
      this.updateEmptyState()
      return
    }

    // Filter milestones
    let visibleCount = 0
    let exactMatch = false

    milestoneOptions.forEach(el => {
      const name = el.dataset.milestoneName.toLowerCase()
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

  selectMilestone(event) {
    const milestoneOption = event.target.closest(".milestone-option")
    const milestoneId = milestoneOption.dataset.milestoneId
    const milestoneName = milestoneOption.dataset.milestoneName

    // Update selected milestone ID
    this.selectedMilestoneIdValue = milestoneId === "" ? null : parseInt(milestoneId)

    // Update hidden field
    this.updateHiddenField()

    // Update button display
    this.updateButtonDisplay(milestoneName)

    // Close picker
    this.close()
  }

  async createAndSelectMilestone() {
    const name = this.searchTarget.value.trim()
    if (!name) return

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/milestones`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          milestone: { name }
        })
      })

      if (response.ok) {
        const milestone = await response.json()

        // Add to milestones array
        this.allMilestones.push(milestone)

        // Re-render to include new milestone
        this.renderMilestones()

        // Automatically select the new milestone
        this.selectedMilestoneIdValue = milestone.id

        // Check the new milestone's radio button
        const newMilestoneElement = this.milestoneListTarget.querySelector(`[data-milestone-id="${milestone.id}"]`)
        if (newMilestoneElement) {
          const radio = newMilestoneElement.querySelector("input[type=radio]")
          radio.checked = true
        }

        // Update hidden field and display
        this.updateHiddenField()
        this.updateButtonDisplay(milestone.name)

        // Clear search
        this.searchTarget.value = ""
        this.filterMilestones()

        // Close picker
        this.close()
      } else {
        const error = await response.json()
        console.error("Failed to create milestone:", error)
      }
    } catch (error) {
      console.error("Failed to create milestone:", error)
    }
  }

  updateHiddenField() {
    // Find the hidden field target
    if (!this.hasTarget("hiddenField")) return

    // Update the hidden field value
    this.hiddenFieldTarget.value = this.selectedMilestoneIdValue || ""
  }

  updateButtonDisplay(milestoneName) {
    // Update the button label to show milestone name
    const button = this.element.closest('.relative').querySelector('button')
    if (!button) return

    const labelSpan = button.querySelector('[data-issue-form-target="milestoneLabel"]')
    if (!labelSpan) return

    labelSpan.textContent = milestoneName || "No milestone"
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
    if (this.hasLoadingStateTarget) {
      this.loadingStateTarget.classList.remove("hidden")
    }
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.add("hidden")
    }
  }

  hideLoading() {
    if (this.hasLoadingStateTarget) {
      this.loadingStateTarget.classList.add("hidden")
    }
  }

  updateEmptyState() {
    if (!this.hasEmptyStateTarget) return

    const milestoneOptions = this.milestoneListTarget.querySelectorAll(".milestone-option")
    const hasVisibleMilestones = Array.from(milestoneOptions).some(el => !el.classList.contains("hidden"))
    const createVisible = !this.createOptionTarget.classList.contains("hidden")

    if (!hasVisibleMilestones && !createVisible) {
      this.emptyStateTarget.classList.remove("hidden")
    } else {
      this.emptyStateTarget.classList.add("hidden")
    }
  }
}
