import { Controller } from "@hotwired/stimulus";
import { trackFeature } from "vektis";

// Filters which group (#list_group_*) is visible on mobile. The `.mobile-group-hidden`
// class is only active below the sm breakpoint via CSS, so desktop is unaffected.
export default class extends Controller {
  static targets = ["chip"];

  connect() {
    this.activeGroupId = this.chipTargets[0]?.dataset.groupId;
    this.applyFilter();
  }

  select(event) {
    const previousGroupId = this.activeGroupId;
    this.activeGroupId = event.currentTarget.dataset.groupId;
    this.applyFilter();
    this.updateChipStates();

    // connect() calls applyFilter() but never select(), so this cannot fire on page load. The
    // chips only exist inside a sm:hidden container and toggle list-view groups, so the surface
    // is unconditionally "list".
    if (this.activeGroupId !== previousGroupId) {
      trackFeature("issue-filter", "apply", { surface: "list" });
    }
  }

  applyFilter() {
    if (!this.activeGroupId) return;
    document.querySelectorAll('[id^="list_group_"]').forEach((group) => {
      const groupId = group.id.replace("list_group_", "");
      group.classList.toggle("mobile-group-hidden", groupId !== this.activeGroupId);
    });
  }

  updateChipStates() {
    this.chipTargets.forEach((chip) => {
      const isActive = chip.dataset.groupId === this.activeGroupId;
      chip.classList.toggle("bg-foreground", isActive);
      chip.classList.toggle("text-gray-100", isActive);
      chip.classList.toggle("border", isActive);
      chip.classList.toggle("border-stroke", isActive);
      chip.classList.toggle("text-gray-500", !isActive);
    });
  }
}
