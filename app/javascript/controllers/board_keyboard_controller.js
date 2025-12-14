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
  }

  createNewIssue() {
    // For now, just alert - we'll implement a modal later
    alert("Create new issue modal will go here. For now, you can import issues via CSV.")
    console.log("Create new issue")
  }
}
