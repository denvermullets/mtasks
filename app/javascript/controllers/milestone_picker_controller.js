import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "picker", "search", "milestoneList", "createOption", "createButton", "createText",
    "nameField"
  ]

  static values = {
    issueId: Number,
    teamId: Number,
    context: String,
    currentMilestone: Number
  }

  connect() {
    this.currentFocusIndex = -1
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

  open() {
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

  handleCreate(event) {
    // After milestone is created, automatically select it
    if (event.detail.success) {
      // The new milestone option will be appended to the list
      // Wait a moment for DOM to update, then auto-select it
      setTimeout(() => {
        const newMilestone = this.milestoneListTarget.querySelector('.milestone-option:last-child input[type="radio"]')
        if (newMilestone) {
          newMilestone.checked = true
          newMilestone.dispatchEvent(new Event('change', { bubbles: true }))
        }
      }, 100)
    }
  }

  filterMilestones() {
    // Clear previous debounce timeout
    if (this.filterDebounceTimeout) {
      clearTimeout(this.filterDebounceTimeout)
    }

    // Debounce the filtering
    this.filterDebounceTimeout = setTimeout(() => {
      const query = this.searchTarget.value.trim().toLowerCase()
      const milestoneOptions = this.milestoneListTarget.querySelectorAll(".milestone-option")

      if (query === "") {
        // Show all milestones
        milestoneOptions.forEach(el => el.classList.remove("hidden"))
        this.createOptionTarget.classList.add("hidden")
        return
      }

      // Filter milestones
      let exactMatch = false

      milestoneOptions.forEach(el => {
        const name = el.dataset.milestoneName.toLowerCase()
        if (name.includes(query)) {
          el.classList.remove("hidden")
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
        if (this.hasNameFieldTarget) {
          this.nameFieldTarget.value = query
        }
        this.createOptionTarget.classList.remove("hidden")
      } else {
        this.createOptionTarget.classList.add("hidden")
      }

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
