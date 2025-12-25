import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "chevron"]

  toggle(event) {
    event.preventDefault()
    this.listTarget.classList.toggle("hidden")
    this.chevronTarget.classList.toggle("rotate-180")
  }
}
