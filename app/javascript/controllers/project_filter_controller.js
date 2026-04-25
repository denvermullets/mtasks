import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["panel", "badge", "clear"];

  connect() {
    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    document.addEventListener("click", this.boundHandleClickOutside);
  }

  disconnect() {
    document.removeEventListener("click", this.boundHandleClickOutside);
  }

  togglePanel(event) {
    event.stopPropagation();
    this.panelTarget.classList.toggle("hidden");
  }

  closePanel() {
    this.panelTarget.classList.add("hidden");
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.closePanel();
    }
  }

  toggleProject() {
    this.applySelection(this.selectedIds());
  }

  clear() {
    this.panelTarget
      .querySelectorAll('input[type="checkbox"]:checked')
      .forEach((cb) => (cb.checked = false));
    this.applySelection([]);
  }

  selectedIds() {
    return Array.from(this.panelTarget.querySelectorAll('input[type="checkbox"]:checked')).map(
      (cb) => cb.value
    );
  }

  applySelection(ids) {
    const url = new URL(window.location.href);
    if (ids.length > 0) {
      url.searchParams.set("project_ids", ids.join(","));
    } else {
      url.searchParams.delete("project_ids");
    }

    window.history.pushState({}, "", url.toString());
    this.updateBadge(ids.length);

    clearTimeout(this.refreshTimeout);
    this.refreshTimeout = setTimeout(() => {
      window.Turbo.visit(url.toString(), { frame: "issues_board" });
    }, 150);
  }

  updateBadge(count) {
    if (this.hasBadgeTarget) {
      if (count > 0) {
        this.badgeTarget.textContent = `Focus · ${count}`;
        this.badgeTarget.classList.remove("hidden");
      } else {
        this.badgeTarget.textContent = "";
        this.badgeTarget.classList.add("hidden");
      }
    }

    if (this.hasClearTarget) {
      this.clearTarget.classList.toggle("hidden", count === 0);
    }

    const button = this.element.querySelector("button");
    if (button) {
      if (count > 0) {
        button.classList.add("border-accent", "text-gray-100");
        button.classList.remove("border-stroke");
      } else {
        button.classList.remove("border-accent", "text-gray-100");
        button.classList.add("border-stroke");
      }
    }
  }
}
