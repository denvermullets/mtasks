import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = ["picker", "priorityList", "header", "check"];

  static values = {
    issueId: Number,
    teamId: Number,
    context: String,
    currentPriority: String,
  };

  connect() {
    this.currentFocusIndex = -1;
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;

    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    this.boundHandleKeyDown = this.handleKeyDown.bind(this);
  }

  disconnect() {
    this.close();
  }

  // Shared-picker entry point: retarget this single picker at the hovered card,
  // then open. Used by board-keyboard for the 'P' shortcut so we don't render a
  // full priority picker per issue row.
  openForCard(card) {
    this.referenceCard = card;
    this.issueIdValue = parseInt(card.dataset.issueId);

    const currentPriority = card.dataset.currentPriority || "no_priority";
    this.currentPriorityValue = currentPriority;

    if (this.hasHeaderTarget) {
      const identifier = card.dataset.issueIdentifier || "";
      const title = card.dataset.issueTitle || "";
      this.headerTarget.textContent = title ? `${identifier} • ${title}` : identifier;
    }

    this.reflectCurrent(currentPriority);
    this.open();
  }

  reflectCurrent(priority) {
    this.checkTargets.forEach((check) => {
      check.classList.toggle("hidden", check.dataset.priorityValue !== priority);
    });
  }

  open() {
    this.pickerTarget.classList.remove("hidden");
    this.positionOverlay();

    this.currentFocusIndex = -1;
    document.addEventListener("click", this.boundHandleClickOutside);
    document.addEventListener("keydown", this.boundHandleKeyDown);
  }

  close() {
    this.pickerTarget.classList.add("hidden");
    this.currentFocusIndex = -1;

    document.removeEventListener("click", this.boundHandleClickOutside);
    document.removeEventListener("keydown", this.boundHandleKeyDown);
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close();
    }
  }

  handleKeyDown(event) {
    if (!["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) {
      return;
    }

    event.preventDefault();

    if (event.key === "Escape") {
      this.close();
      return;
    }

    const options = this.getOptions();

    if (event.key === "ArrowDown") {
      this.currentFocusIndex = Math.min(this.currentFocusIndex + 1, options.length - 1);
      this.updateFocus(options);
    } else if (event.key === "ArrowUp") {
      this.currentFocusIndex = Math.max(this.currentFocusIndex - 1, 0);
      this.updateFocus(options);
    } else if (event.key === "Enter" && this.currentFocusIndex >= 0) {
      options[this.currentFocusIndex].click();
    }
  }

  getOptions() {
    return Array.from(this.priorityListTarget.querySelectorAll(".priority-option"));
  }

  updateFocus(options) {
    options.forEach((option, index) => {
      if (index === this.currentFocusIndex) {
        option.classList.add("bg-hover-highlight");
        option.scrollIntoView({ block: "nearest" });
      } else {
        option.classList.remove("bg-hover-highlight");
      }
    });
  }

  async selectPriority(event) {
    const option = event.currentTarget.closest(".priority-option");
    const priority = option.dataset.priorityValue;

    await this.updateIssuePriority(priority);
  }

  async updateIssuePriority(priority) {
    if (priority === this.currentPriorityValue) {
      this.close();
      return;
    }

    // Optimistically move the card (when grouped by priority) and close immediately
    const revertInfo = this.optimisticMove(priority);
    this.currentPriorityValue = priority;
    this.close();

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/issues/${this.issueIdValue}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify({
          issue: {
            priority: priority,
          },
        }),
      });

      if (response.ok) {
        this.reflectCurrent(priority);

        // Process the turbo stream response (server is source of truth)
        const turboStream = await response.text();
        Turbo.renderStreamMessage(turboStream);
      } else {
        console.error("Failed to update priority, reverting");
        this.revertOptimisticMove(revertInfo);
      }
    } catch (error) {
      console.error("Error updating priority:", error);
      this.revertOptimisticMove(revertInfo);
    }
  }

  // Display names of the swimlane rows the server renders when sub-grouping by
  // priority (see IssueDisplayService#group_by_priority). Keyed by the raw value
  // stored on the card's data-current-priority.
  static PRIORITY_ROW_NAMES = {
    no_priority: "No Priority",
    urgent: "Urgent",
    high: "High",
    medium: "Medium",
    low: "Low",
  };

  optimisticMove(newPriority) {
    const card = document.getElementById(`issue_${this.issueIdValue}`);
    if (!card) return null;

    const board = document.querySelector("[data-group-by]");
    if (!board) return null;

    // Priority as columns: move the card into the matching column (scoped to its
    // swimlane row if the board is also sub-grouped).
    if (board.dataset.groupBy === "priority") {
      return this.moveWithinColumns(card, newPriority);
    }

    // Priority as swimlane rows: move the card into the matching row, keeping it
    // in the same column.
    if (board.dataset.subGroupBy === "priority") {
      return this.moveBetweenRows(card, newPriority);
    }

    return null;
  }

  moveWithinColumns(card, newPriority) {
    const originalParent = card.parentElement;
    const originalNextSibling = card.nextElementSibling;
    const previousPriority = card.dataset.currentPriority;

    // Scope to the same swimlane row when the board is also sub-grouped.
    const swimlaneRow = card.closest("[data-swimlane-row-name]");
    const scope = swimlaneRow || document;
    const targetContainer = scope.querySelector(
      `[data-group-container="${newPriority}"]`
    );

    if (!targetContainer) return null;

    card.classList.add("optimistic-moving");
    card.dataset.currentPriority = newPriority;
    targetContainer.prepend(card);

    setTimeout(() => card.classList.remove("optimistic-moving"), 300);

    this.updateColumnCount(previousPriority, -1);
    this.updateColumnCount(newPriority, 1);

    return { mode: "column", card, originalParent, originalNextSibling, previousPriority };
  }

  moveBetweenRows(card, newPriority) {
    const originalParent = card.parentElement;
    const originalNextSibling = card.nextElementSibling;
    const previousPriority = card.dataset.currentPriority;
    const previousRow = card.closest("[data-swimlane-row-name]");

    const rowName = this.constructor.PRIORITY_ROW_NAMES[newPriority];
    const targetRow = rowName
      ? document.querySelector(`[data-swimlane-row-name="${rowName}"]`)
      : null;
    if (!targetRow) return null;

    // Keep the card in the same column — match its current column container by
    // group value within the destination row.
    const columnKey = originalParent?.dataset.groupContainer ?? "";
    const targetContainer = targetRow.querySelector(
      `[data-group-container="${columnKey}"]`
    );
    if (!targetContainer) return null;

    card.classList.add("optimistic-moving");
    card.dataset.currentPriority = newPriority;
    targetContainer.prepend(card);

    setTimeout(() => card.classList.remove("optimistic-moving"), 300);

    this.syncRow(previousRow);
    this.syncRow(targetRow);

    return { mode: "row", card, originalParent, originalNextSibling, previousPriority, previousRow, targetRow };
  }

  revertOptimisticMove(revertInfo) {
    if (!revertInfo) return;
    const { mode, card, originalParent, originalNextSibling, previousPriority } = revertInfo;

    if (!document.contains(card)) return;

    const currentPriority = card.dataset.currentPriority;
    card.dataset.currentPriority = previousPriority;
    this.currentPriorityValue = previousPriority;

    if (originalNextSibling && document.contains(originalNextSibling)) {
      originalParent.insertBefore(card, originalNextSibling);
    } else if (document.contains(originalParent)) {
      originalParent.appendChild(card);
    }

    if (mode === "row") {
      this.syncRow(revertInfo.targetRow);
      this.syncRow(revertInfo.previousRow);
    } else {
      this.updateColumnCount(currentPriority, -1);
      this.updateColumnCount(previousPriority, 1);
    }
  }

  // Recompute a swimlane row's issue count and expand/collapse it to match the
  // server's empty-row behavior.
  syncRow(rowEl) {
    if (!rowEl) return;

    const content = rowEl.querySelector('[data-swimlane-row-target="content"]');
    const chevron = rowEl.querySelector('[data-swimlane-row-target="chevron"]');
    const count = content ? content.querySelectorAll("[data-issue-id]").length : 0;

    const countSpan = rowEl.querySelector("[data-swimlane-row-count]");
    if (countSpan) countSpan.textContent = count;

    if (content && chevron) {
      content.classList.toggle("hidden", count === 0);
      chevron.classList.toggle("-rotate-90", count === 0);
    }
  }

  updateColumnCount(priority, delta) {
    if (priority == null) return;
    document.querySelectorAll(`[data-group-count="${priority}"]`).forEach((countSpan) => {
      const current = parseInt(countSpan.textContent.trim()) || 0;
      countSpan.textContent = Math.max(0, current + delta);
    });
  }

  positionOverlay() {
    const overlayWidth = 256; // w-64 = 16rem = 256px
    const overlayHeight = 260; // approximate
    let referenceElement = null;
    let rect = null;

    if (this.contextValue === "card") {
      referenceElement = this.referenceCard || this.element.closest('[data-hovered="true"]');
      if (!referenceElement) return;
      rect = referenceElement.getBoundingClientRect();

      const isWideElement = rect.width > 800;

      let top = rect.top;
      let left;

      if (isWideElement) {
        left = (window.innerWidth - overlayWidth) / 2;
      } else {
        left = rect.left - overlayWidth - 8; // 8px gap

        if (left < 8) {
          left = rect.right + 8;
        }

        if (left + overlayWidth > window.innerWidth - 8) {
          left = (window.innerWidth - overlayWidth) / 2;
        }
      }

      if (top + overlayHeight > window.innerHeight) {
        top = window.innerHeight - overlayHeight - 8;
      }
      if (top < 8) {
        top = 8;
      }

      this.pickerTarget.style.top = `${top}px`;
      this.pickerTarget.style.left = `${left}px`;
    }
  }
}
