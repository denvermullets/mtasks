import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = ["search", "resultsList", "emptyState", "loadingState"];

  static values = {
    issueId: Number,
    teamId: Number,
    direction: String,
    currentIds: Array,
  };

  connect() {
    this.currentFocusIndex = -1;
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    this.filterDebounceTimeout = null;
    this.loaded = false;
  }

  // Called when the dropdown becomes visible — trigger initial search
  searchTargetConnected() {
    // Use a mutation observer-free approach: search when the input is focused
  }

  focusSearch() {
    if (!this.loaded) {
      this.loaded = true;
      this.searchIssues();
    }
    this.searchTarget.focus();
  }

  filterIssues() {
    if (this.filterDebounceTimeout) {
      clearTimeout(this.filterDebounceTimeout);
    }
    this.filterDebounceTimeout = setTimeout(() => {
      this.searchIssues();
    }, 300);
  }

  handleKeyDown(event) {
    if (!["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) return;
    event.preventDefault();

    switch (event.key) {
      case "ArrowDown":
        this.focusNext();
        break;
      case "ArrowUp":
        this.focusPrevious();
        break;
      case "Enter":
        this.selectFocused();
        break;
      case "Escape":
        this.searchTarget.blur();
        break;
    }
  }

  focusNext() {
    const options = this.getVisibleOptions();
    if (options.length === 0) return;
    this.currentFocusIndex = (this.currentFocusIndex + 1) % options.length;
    this.updateVisualFocus(options);
  }

  focusPrevious() {
    const options = this.getVisibleOptions();
    if (options.length === 0) return;
    this.currentFocusIndex =
      this.currentFocusIndex <= 0 ? options.length - 1 : this.currentFocusIndex - 1;
    this.updateVisualFocus(options);
  }

  getVisibleOptions() {
    return Array.from(this.resultsListTarget.querySelectorAll(".dependency-option"));
  }

  updateVisualFocus(options) {
    options.forEach((el) => el.classList.remove("bg-hover-highlight"));
    if (this.currentFocusIndex >= 0 && this.currentFocusIndex < options.length) {
      options[this.currentFocusIndex].classList.add("bg-hover-highlight");
      options[this.currentFocusIndex].scrollIntoView({ block: "nearest" });
    }
  }

  selectFocused() {
    const options = this.getVisibleOptions();
    if (this.currentFocusIndex < 0 || this.currentFocusIndex >= options.length) return;
    const focused = options[this.currentFocusIndex];
    const checkbox = focused.querySelector("input[type=checkbox]");
    checkbox.checked = !checkbox.checked;
    this.toggleDependency({ target: checkbox });
  }

  async searchIssues() {
    const query = this.searchTarget.value.trim();

    try {
      if (this.hasLoadingStateTarget) {
        this.loadingStateTarget.classList.remove("hidden");
      }

      const url = new URL(
        `/teams/${this.teamIdValue}/issues/search`,
        window.location.origin
      );
      url.searchParams.set("q", query);
      url.searchParams.set("exclude_id", this.issueIdValue);

      const response = await fetch(url, {
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken,
        },
      });

      if (!response.ok) throw new Error("Search failed");

      const issues = await response.json();
      this.renderResults(issues);
    } catch (error) {
      console.error("Failed to search issues:", error);
    } finally {
      if (this.hasLoadingStateTarget) {
        this.loadingStateTarget.classList.add("hidden");
      }
    }
  }

  renderResults(issues) {
    this.currentFocusIndex = -1;
    const currentIds = this.currentIdsValue;

    if (issues.length === 0) {
      this.resultsListTarget.innerHTML = "";
      this.emptyStateTarget.classList.remove("hidden");
      return;
    }

    this.emptyStateTarget.classList.add("hidden");

    this.resultsListTarget.innerHTML = issues
      .map((issue) => {
        const isSelected = currentIds.includes(issue.id);
        return `
        <label class="dependency-option flex items-center gap-2 px-3 py-2 text-sm hover:bg-hover-highlight transition-colors cursor-pointer"
               data-issue-id="${issue.id}">
          <input type="checkbox"
                 ${isSelected ? "checked" : ""}
                 data-action="change->issue-dependency-picker#toggleDependency"
                 class="rounded border-stroke text-accent focus:ring-accent bg-background">
          <span class="font-mono text-xs text-gray-500 shrink-0">${issue.identifier}</span>
          <span class="text-gray-300 truncate">${this.escapeHtml(issue.title)}</span>
        </label>
      `;
      })
      .join("");
  }

  async toggleDependency(event) {
    const checkbox = event.target;
    const option = checkbox.closest(".dependency-option");
    const targetIssueId = parseInt(option.dataset.issueId);
    const isChecked = checkbox.checked;

    try {
      if (isChecked) {
        await this.addDependency(targetIssueId);
      } else {
        await this.removeDependency(targetIssueId);
      }
    } catch (error) {
      checkbox.checked = !isChecked;
      console.error("Failed to toggle dependency:", error);
    }
  }

  async addDependency(targetIssueId) {
    const response = await fetch(
      `/teams/${this.teamIdValue}/issues/${this.issueIdValue}/issue_dependencies`,
      {
        method: "POST",
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify({
          target_issue_id: targetIssueId,
          direction: this.directionValue,
        }),
      }
    );

    if (!response.ok) throw new Error("Failed to add dependency");

    const html = await response.text();
    Turbo.renderStreamMessage(html);
  }

  async removeDependency(targetIssueId) {
    const response = await fetch(
      `/teams/${this.teamIdValue}/issues/${this.issueIdValue}/issue_dependencies/${targetIssueId}`,
      {
        method: "DELETE",
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.csrfToken,
        },
      }
    );

    if (!response.ok) throw new Error("Failed to remove dependency");

    const html = await response.text();
    Turbo.renderStreamMessage(html);
  }

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }
}
