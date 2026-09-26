import { Controller } from "@hotwired/stimulus";

// Board toolbar "Dependencies" switch. Flips the show_dependencies param, reloads only the
// issues_board frame (so search and filters carry over), and saves the choice as this user's
// team default straight away.
export default class extends Controller {
  static targets = ["track", "knob"];
  static values = { on: Boolean, url: String };

  toggle() {
    this.onValue = !this.onValue;

    const url = new URL(window.location.href);
    url.searchParams.set("show_dependencies", this.onValue);
    window.history.pushState({}, "", url.toString());
    window.Turbo.visit(url.toString(), { frame: "issues_board" });

    this.persist();
    // Lets the display options panel keep its "Save as default" comparison in sync.
    this.dispatch("changed", { target: window, detail: { on: this.onValue } });
  }

  onValueChanged(on) {
    if (!this.hasTrackTarget) return;

    this.element.setAttribute("aria-checked", on);
    this.element.classList.toggle("border-accent", on);
    this.element.classList.toggle("text-gray-100", on);
    this.element.classList.toggle("border-stroke", !on);
    this.trackTarget.classList.toggle("bg-accent", on);
    this.trackTarget.classList.toggle("bg-gray-600", !on);
    this.knobTarget.classList.toggle("translate-x-3", on);
    this.knobTarget.classList.toggle("translate-x-0", !on);
    this.syncLegend();
  }

  // The toolbar sits outside the board frame, so it learns about view mode switches from the
  // frame's own markup after each load.
  syncViewMode(event) {
    if (event.target.id !== "issues_board") return;

    const viewMode = event.target.querySelector("[data-view-mode]")?.dataset.viewMode;
    if (!viewMode) return;

    this.board = viewMode === "board";
    this.element.classList.toggle("hidden", !this.board);
    this.syncLegend();
  }

  // Legend only on wide screens, where the toolbar has room for it.
  syncLegend() {
    const board = this.board ?? !this.element.classList.contains("hidden");
    document.getElementById("dependency_legend")?.classList.toggle("xl:block", board && this.onValue);
  }

  persist() {
    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
      },
      body: JSON.stringify({ show_dependencies: this.onValue }),
    }).catch(() => {});
  }
}
