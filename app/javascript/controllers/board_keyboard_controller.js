import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.boundHandleKeyPress = this.handleKeyPress.bind(this)
    document.addEventListener("keydown", this.boundHandleKeyPress)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeyPress)
  }

  handleKeyPress(event) {
    // Ignore if user is typing in an input field
    if (event.target.matches('input, textarea, select')) {
      return
    }

    // Press 'C' to create new issue
    if (event.key === 'c' || event.key === 'C') {
      event.preventDefault()
      this.createNewIssue()
    }

    // Press 'L' to open label picker on hovered card
    if (event.key === 'l' || event.key === 'L') {
      event.preventDefault()
      this.openLabelPicker()
    }
  }

  openLabelPicker() {
    // Find the currently hovered card
    const hoveredCard = document.querySelector('[data-hovered="true"]')
    if (!hoveredCard) {
      return
    }

    // Find the label picker inside the hovered card
    const labelPicker = hoveredCard.querySelector('[data-controller="label-picker"]')
    if (!labelPicker) {
      return
    }

    // Get the label picker controller and open it
    const controller = this.application.getControllerForElementAndIdentifier(labelPicker, "label-picker")
    if (controller && controller.open) {
      controller.open()
    }
  }

  createNewIssue() {
    // Get the team ID from the URL path
    const pathParts = window.location.pathname.split('/')
    const teamIndex = pathParts.indexOf('teams')
    if (teamIndex !== -1 && pathParts[teamIndex + 1]) {
      const teamId = pathParts[teamIndex + 1]
      window.location.href = `/teams/${teamId}/issues/new`
    } else {
      console.error("Could not determine team ID from URL")
    }
  }
}
