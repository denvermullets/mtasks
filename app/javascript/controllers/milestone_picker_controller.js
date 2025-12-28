import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "picker", "search", "milestoneList", "createOption", "createButton", "createText",
    "emptyState", "loadingState"
  ]

  static values = {
    issueId: Number,
    teamId: Number,
    context: String,
    currentMilestone: Number
  }

  connect() {
    this.currentFocusIndex = -1
    this.allMilestones = []
    this.filteredMilestones = []
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
    // Load milestones data
    await this.loadMilestones()

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
      this.showError()
    } finally {
      this.hideLoading()
    }
  }

  renderMilestones() {
    // Clear list
    this.milestoneListTarget.innerHTML = ""

    // Add "No milestone" option first
    this.milestoneListTarget.appendChild(this.createNoMilestoneElement())

    // Add divider
    const divider = document.createElement("div")
    divider.className = "border-t border-stroke my-1"
    this.milestoneListTarget.appendChild(divider)

    // Add all milestones (already sorted by due_date from backend)
    this.allMilestones.forEach(milestone => {
      this.milestoneListTarget.appendChild(this.createMilestoneElement(milestone))
    })

    this.filteredMilestones = Array.from(this.milestoneListTarget.querySelectorAll(".milestone-option"))
    this.updateEmptyState()
  }

  createNoMilestoneElement() {
    const label = document.createElement("label")
    label.className = "milestone-option flex items-center px-3 py-2 text-sm text-gray-500 hover:bg-hover-highlight transition-colors cursor-pointer"
    label.dataset.milestoneId = ""
    label.dataset.milestoneName = "No milestone"
    label.setAttribute("role", "option")

    const isSelected = !this.currentMilestoneValue

    label.innerHTML = `
      <input type="radio"
             name="milestone"
             ${isSelected ? "checked" : ""}
             class="mr-2 rounded-full bg-background border-stroke accent-accent focus:ring-0 focus:ring-offset-0"
             data-action="change->milestone-picker#selectMilestone" />
      <span class="text-gray-500 mr-2">◇</span>
      <span class="flex-1">No milestone</span>
      ${isSelected ? '<span class="text-accent">✓</span>' : ''}
    `

    return label
  }

  createMilestoneElement(milestone) {
    const label = document.createElement("label")
    label.className = "milestone-option flex items-center px-3 py-2 text-sm text-gray-300 hover:bg-hover-highlight transition-colors cursor-pointer"
    label.dataset.milestoneId = milestone.id
    label.dataset.milestoneName = milestone.name
    label.setAttribute("role", "option")

    const isSelected = this.currentMilestoneValue === milestone.id

    label.innerHTML = `
      <input type="radio"
             name="milestone"
             ${isSelected ? "checked" : ""}
             class="mr-2 rounded-full bg-background border-stroke accent-accent focus:ring-0 focus:ring-offset-0"
             data-action="change->milestone-picker#selectMilestone" />
      <span style="color: ${milestone.status_color};" class="mr-2">◆</span>
      <span class="flex-1 truncate">${milestone.name}</span>
      ${milestone.formatted_due_date ? `<span class="text-xs text-gray-500">• ${milestone.formatted_due_date}</span>` : ''}
      ${isSelected ? '<span class="text-accent ml-2">✓</span>' : ''}
    `

    return label
  }

  filterMilestones() {
    // Clear previous debounce timeout
    if (this.filterDebounceTimeout) {
      clearTimeout(this.filterDebounceTimeout)
    }

    // Debounce the filtering
    this.filterDebounceTimeout = setTimeout(() => {
      const query = this.searchTarget.value.trim().toLowerCase()

      if (query === "") {
        // Show all milestones
        this.filteredMilestones.forEach(el => el.classList.remove("hidden"))
        this.createOptionTarget.classList.add("hidden")
        this.updateEmptyState()
        return
      }

      // Filter milestones
      let visibleCount = 0
      let exactMatch = false

      this.filteredMilestones.forEach(el => {
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
      this.currentFocusIndex = -1
    }, 300)
  }

  handleKeyDown(event) {
    // Don't interfere with normal typing
    if (!["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) {
      return
    }

    event.preventDefault()

    if (event.key === "Escape") {
      this.close()
      return
    }

    const visibleOptions = this.getVisibleOptions()

    if (event.key === "ArrowDown") {
      this.currentFocusIndex = Math.min(this.currentFocusIndex + 1, visibleOptions.length - 1)
      this.updateFocus(visibleOptions)
    } else if (event.key === "ArrowUp") {
      this.currentFocusIndex = Math.max(this.currentFocusIndex - 1, 0)
      this.updateFocus(visibleOptions)
    } else if (event.key === "Enter" && this.currentFocusIndex >= 0) {
      visibleOptions[this.currentFocusIndex].querySelector('input').click()
    }
  }

  getVisibleOptions() {
    return Array.from(this.milestoneListTarget.querySelectorAll(".milestone-option:not(.hidden)"))
  }

  updateFocus(options) {
    options.forEach((option, index) => {
      if (index === this.currentFocusIndex) {
        option.classList.add("bg-hover-highlight")
        option.scrollIntoView({ block: "nearest" })
      } else {
        option.classList.remove("bg-hover-highlight")
      }
    })
  }

  async selectMilestone(event) {
    const milestoneOption = event.target.closest(".milestone-option")
    const milestoneId = milestoneOption.dataset.milestoneId

    await this.updateIssueMilestone(milestoneId === "" ? null : parseInt(milestoneId))
  }

  async updateIssueMilestone(milestoneId) {
    try {
      const response = await fetch(`/teams/${this.teamIdValue}/issues/${this.issueIdValue}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          issue: {
            milestone_id: milestoneId
          }
        })
      })

      if (response.ok) {
        this.currentMilestoneValue = milestoneId || 0

        // Get the turbo stream response and let Turbo handle it
        const turboStream = await response.text()
        Turbo.renderStreamMessage(turboStream)

        this.close()
      } else {
        console.error("Failed to update milestone")
      }
    } catch (error) {
      console.error("Error updating milestone:", error)
    }
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
        await this.updateIssueMilestone(milestone.id)
      } else {
        console.error("Failed to create milestone")
      }
    } catch (error) {
      console.error("Error creating milestone:", error)
    }
  }

  updateEmptyState() {
    const visibleCount = this.getVisibleOptions().length

    if (this.hasEmptyStateTarget) {
      if (visibleCount === 0 && this.searchTarget.value.trim() !== "") {
        this.emptyStateTarget.classList.remove("hidden")
      } else {
        this.emptyStateTarget.classList.add("hidden")
      }
    }
  }

  showLoading() {
    if (this.hasLoadingStateTarget) {
      this.loadingStateTarget.classList.remove("hidden")
    }
  }

  hideLoading() {
    if (this.hasLoadingStateTarget) {
      this.loadingStateTarget.classList.add("hidden")
    }
  }

  showError() {
    // TODO: Implement error state
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
      // For sidebar context, find the milestone dropdown button
      referenceElement = this.element.closest('[data-issue-sidebar-target="milestoneDropdown"]')
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
}
