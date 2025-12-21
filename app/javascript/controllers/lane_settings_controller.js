import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["addLaneForm", "lanesList", "newLaneName", "newLaneColor", "newLanePosition", "laneRow"]
  static values = { teamId: Number }

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
  }

  async moveLaneUp(event) {
    const button = event.currentTarget
    const laneRow = button.closest('[data-lane-id]')
    const laneId = laneRow.dataset.laneId
    const currentIndex = Array.from(this.laneRowTargets).indexOf(laneRow)

    if (currentIndex === 0) return // Already at top

    const newPosition = currentIndex - 1

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/lanes/${laneId}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ lane: { position: newPosition } })
      })

      if (response.ok) {
        // Move element in DOM
        const previousRow = this.laneRowTargets[currentIndex - 1]
        this.lanesListTarget.insertBefore(laneRow, previousRow)
        this.updatePositionNumbers()
      } else {
        alert("Failed to reorder lane")
      }
    } catch (error) {
      console.error("Failed to move lane up:", error)
      alert("Failed to move lane up")
    }
  }

  async moveLaneDown(event) {
    const button = event.currentTarget
    const laneRow = button.closest('[data-lane-id]')
    const laneId = laneRow.dataset.laneId
    const currentIndex = Array.from(this.laneRowTargets).indexOf(laneRow)

    if (currentIndex === this.laneRowTargets.length - 1) return // Already at bottom

    const newPosition = currentIndex + 1

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/lanes/${laneId}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ lane: { position: newPosition } })
      })

      if (response.ok) {
        // Move element in DOM
        const nextRow = this.laneRowTargets[currentIndex + 1]
        if (nextRow.nextSibling) {
          this.lanesListTarget.insertBefore(laneRow, nextRow.nextSibling)
        } else {
          this.lanesListTarget.appendChild(laneRow)
        }
        this.updatePositionNumbers()
      } else {
        alert("Failed to reorder lane")
      }
    } catch (error) {
      console.error("Failed to move lane down:", error)
      alert("Failed to move lane down")
    }
  }

  updatePositionNumbers() {
    this.laneRowTargets.forEach((row, index) => {
      const positionSpan = row.querySelector('span.font-mono')
      if (positionSpan) {
        positionSpan.textContent = `#${index + 1}`
      }
    })
  }

  toggleAddLaneForm() {
    this.addLaneFormTarget.classList.toggle("hidden")

    if (!this.addLaneFormTarget.classList.contains("hidden")) {
      // Focus on name input when form is shown
      if (this.hasNewLaneNameTarget) {
        this.newLaneNameTarget.focus()
      }

      // Set default position to end
      if (this.hasNewLanePositionTarget && this.hasLaneRowTarget) {
        this.newLanePositionTarget.value = this.laneRowTargets.length
      }
    } else {
      // Reset form when hiding
      if (this.hasNewLaneNameTarget) this.newLaneNameTarget.value = ""
      if (this.hasNewLaneColorTarget) this.newLaneColorTarget.value = "#94a3b8"
      if (this.hasNewLanePositionTarget) this.newLanePositionTarget.value = ""
    }
  }

  selectPresetColor(event) {
    event.preventDefault()
    const color = event.currentTarget.dataset.color
    if (this.hasNewLaneColorTarget) {
      this.newLaneColorTarget.value = color
    }
  }

  async createLane(event) {
    event.preventDefault()

    const name = this.newLaneNameTarget.value.trim()
    const color = this.newLaneColorTarget.value
    let position = this.newLanePositionTarget.value

    if (!name) {
      alert("Lane name is required")
      return
    }

    // Default to end if position is empty
    if (position === "" || position === null) {
      position = this.laneRowTargets.length
    }

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/lanes`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          lane: {
            name: name,
            color: color,
            position: parseInt(position)
          }
        })
      })

      if (response.ok) {
        // Reload page to show new lane
        window.location.reload()
      } else {
        const error = await response.json()
        alert(`Error: ${error.errors.join(", ")}`)
      }
    } catch (error) {
      console.error("Failed to create lane:", error)
      alert("Failed to create lane")
    }
  }

  async updateLaneName(event) {
    const input = event.target
    const laneId = input.dataset.laneId
    const newName = input.value.trim()
    const originalValue = input.dataset.originalValue

    if (!newName) {
      input.value = originalValue
      return
    }

    if (newName === originalValue) {
      return
    }

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/lanes/${laneId}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ lane: { name: newName } })
      })

      if (response.ok) {
        const data = await response.json()
        input.dataset.originalValue = data.name
        input.value = data.name
      } else {
        const error = await response.json()
        alert(`Error: ${error.errors.join(", ")}`)
        input.value = originalValue
      }
    } catch (error) {
      console.error("Failed to update lane:", error)
      input.value = originalValue
    }
  }

  handleLaneNameKeydown(event) {
    if (event.key === "Escape") {
      event.target.value = event.target.dataset.originalValue
      event.target.blur()
    } else if (event.key === "Enter") {
      event.target.blur()
    }
  }

  async updateLaneColor(event) {
    const input = event.target
    const laneId = input.dataset.laneId
    const newColor = input.value

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/lanes/${laneId}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ lane: { color: newColor } })
      })

      if (!response.ok) {
        alert("Failed to update color")
      }
    } catch (error) {
      console.error("Failed to update lane color:", error)
    }
  }

  async deleteLane(event) {
    const button = event.currentTarget
    const laneId = button.dataset.laneId
    const hasIssues = button.dataset.hasIssues === "true"

    if (!confirm("Are you sure you want to delete this lane?")) {
      return
    }

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/lanes/${laneId}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": this.csrfToken
        }
      })

      if (response.ok) {
        // Remove lane row from UI
        button.closest('[data-lane-id]').remove()
        this.updatePositionNumbers()
      } else if (response.status === 422) {
        // Lane has issues or other error, show reassignment UI
        const data = await response.json()

        if (data.requires_reassignment) {
          this.showReassignmentModal(laneId, data)
        } else {
          alert(data.error)
        }
      } else {
        alert("Failed to delete lane")
      }
    } catch (error) {
      console.error("Failed to delete lane:", error)
      alert("Failed to delete lane")
    }
  }

  showReassignmentModal(laneId, data) {
    // Create modal overlay
    const modal = document.createElement('div')
    modal.className = "fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
    modal.innerHTML = `
      <div class="bg-foreground border border-stroke rounded-lg p-6 max-w-md w-full mx-4">
        <h3 class="text-lg font-semibold text-gray-200 mb-4">Reassign Issues</h3>
        <p class="text-sm text-gray-400 mb-4">
          This lane has ${data.issue_count} issue(s).
          Please select a lane to move them to:
        </p>
        <select class="w-full px-3 py-2 bg-background border border-stroke rounded text-gray-200 mb-4 focus:outline-none focus:border-accent"
                id="target-lane-select">
          <option value="">Select a lane...</option>
          ${data.available_lanes.map(lane =>
            `<option value="${lane.id}">${lane.name}</option>`
          ).join('')}
        </select>
        <div class="flex gap-2 justify-end">
          <button class="px-4 py-2 text-gray-400 hover:text-gray-200 rounded"
                  data-action="cancel">
            Cancel
          </button>
          <button class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
                  data-action="confirm"
                  data-lane-id="${laneId}">
            Delete Lane
          </button>
        </div>
      </div>
    `

    // Add event listeners
    const cancelBtn = modal.querySelector('[data-action="cancel"]')
    const confirmBtn = modal.querySelector('[data-action="confirm"]')
    const selectElement = modal.querySelector('#target-lane-select')

    cancelBtn.addEventListener('click', () => {
      modal.remove()
    })

    confirmBtn.addEventListener('click', async () => {
      const targetLaneId = selectElement.value
      if (!targetLaneId) {
        alert("Please select a target lane")
        return
      }

      await this.confirmReassignmentAndDelete(laneId, targetLaneId)
      modal.remove()
    })

    // Close on escape key
    const escapeHandler = (e) => {
      if (e.key === "Escape") {
        modal.remove()
        document.removeEventListener('keydown', escapeHandler)
      }
    }
    document.addEventListener('keydown', escapeHandler)

    document.body.appendChild(modal)
  }

  async confirmReassignmentAndDelete(laneId, targetLaneId) {
    try {
      const response = await fetch(`/teams/${this.teamIdValue}/lanes/${laneId}?target_lane_id=${targetLaneId}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": this.csrfToken
        }
      })

      if (response.ok) {
        // Reload page to show updated lanes
        window.location.reload()
      } else {
        const data = await response.json()
        alert(data.error || "Failed to delete lane")
      }
    } catch (error) {
      console.error("Failed to delete lane:", error)
      alert("Failed to delete lane")
    }
  }
}
