import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown"]

  connect() {
    this.boundHandleClickOutside = this.handleClickOutside.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.boundHandleClickOutside)
  }

  toggleDropdown(event) {
    event.stopPropagation()
    event.preventDefault()

    const isHidden = this.dropdownTarget.classList.contains("hidden")

    // Close all other team menus first
    document.querySelectorAll('[data-controller="team-menu"]').forEach(menu => {
      const dropdown = menu.querySelector('[data-team-menu-target="dropdown"]')
      if (dropdown && dropdown !== this.dropdownTarget) {
        dropdown.classList.add("hidden")
      }
    })

    this.dropdownTarget.classList.toggle("hidden")

    if (isHidden) {
      // Just opened, add click listener
      setTimeout(() => {
        document.addEventListener("click", this.boundHandleClickOutside)
      }, 0)
    } else {
      // Just closed, remove click listener
      document.removeEventListener("click", this.boundHandleClickOutside)
    }
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.classList.add("hidden")
      document.removeEventListener("click", this.boundHandleClickOutside)
    }
  }
}
