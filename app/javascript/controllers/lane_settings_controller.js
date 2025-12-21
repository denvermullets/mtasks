import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["addLaneForm"]

  toggleAddLaneForm() {
    this.addLaneFormTarget.classList.toggle("hidden")
  }
}
