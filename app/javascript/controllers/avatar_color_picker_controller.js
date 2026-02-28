import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["popover"]

  toggle(event) {
    event.stopPropagation()
    this.popoverTarget.classList.toggle("hidden")
  }

  close() {
    this.popoverTarget.classList.add("hidden")
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  connect() {
    this._clickOutside = this.clickOutside.bind(this)
    document.addEventListener("click", this._clickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this._clickOutside)
  }
}
