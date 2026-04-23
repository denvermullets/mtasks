import { Controller } from "@hotwired/stimulus";

// Filters which group (#list_group_*) is visible on mobile. The `.mobile-group-hidden`
// class is only active below the sm breakpoint via CSS, so desktop is unaffected.
export default class extends Controller {
  static targets = ["chip"];

  connect() {
    this.activeGroupId = this.chipTargets[0]?.dataset.groupId;
    this.applyFilter();
  }

  select(event) {
    this.activeGroupId = event.currentTarget.dataset.groupId;
    this.applyFilter();
    this.updateChipStates();
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
