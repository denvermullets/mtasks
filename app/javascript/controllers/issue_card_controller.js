import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("Issue card connected:", this.element.dataset.issueId)
  }

  click(event) {
    // Prevent default if needed
    const issueId = this.element.dataset.issueId
    console.log("Issue clicked:", issueId)

    // TODO: Open issue detail modal or navigate to issue page
    // For now, just log it
  }

  contextMenu(event) {
    event.preventDefault()
    const issueId = this.element.dataset.issueId
    console.log("Context menu for issue:", issueId)

    // TODO: Show context menu for quick actions
    // - Change status
    // - Assign to user
    // - Change priority
    // - Archive
  }

  mouseEnter() {
    // Mark this card as hovered so keyboard shortcuts can target it
    this.element.dataset.hovered = "true"
  }

  mouseLeave() {
    // Remove hover state
    delete this.element.dataset.hovered
  }

  handleLabelChange() {
    // Refresh the card to show updated labels
    // Find the closest turbo frame or refresh the whole board view
    const frame = document.querySelector('turbo-frame#issues_board')
    if (frame) {
      frame.reload()
    }
  }
}
