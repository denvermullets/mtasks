// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import * as ActiveStorage from "@rails/activestorage"
import "controllers"

ActiveStorage.start()

// Custom Turbo Stream action: updates innerHTML while preserving scroll positions
Turbo.StreamActions.update_preserving_scroll = function () {
  this.targetElements.forEach((target) => {
    // Save scroll positions of scrollable elements by ID
    const savedById = new Map()
    target.querySelectorAll("[id]").forEach((el) => {
      if (el.scrollTop || el.scrollLeft) {
        savedById.set(el.id, { top: el.scrollTop, left: el.scrollLeft })
      }
    })

    // Save scroll positions of overflow containers by DOM index
    const overflowSelector = ".overflow-auto, .overflow-y-auto, .overflow-x-auto"
    const savedByIndex = []
    target.querySelectorAll(overflowSelector).forEach((el, i) => {
      if (el.scrollTop || el.scrollLeft) {
        savedByIndex.push({ index: i, top: el.scrollTop, left: el.scrollLeft })
      }
    })

    // Perform the update
    target.innerHTML = this.templateElement.innerHTML

    // Restore by ID (most reliable)
    savedById.forEach((pos, id) => {
      const el = document.getElementById(id)
      if (el) {
        el.scrollTop = pos.top
        el.scrollLeft = pos.left
      }
    })

    // Restore by index for non-ID overflow containers
    const newOverflow = target.querySelectorAll(overflowSelector)
    savedByIndex.forEach(({ index, top, left }) => {
      if (newOverflow[index]) {
        newOverflow[index].scrollTop = top
        newOverflow[index].scrollLeft = left
      }
    })
  })
}
