import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = [
    "picker",
    "search",
    "labelList",
    "createOption",
    "createButton",
    "createText",
    "frequentlyUsedSection",
    "frequentlyUsedList",
    "allLabelsList",
    "allLabelsHeader",
    "emptyState",
    "loadingState",
  ];

  static values = {
    issueId: Number,
    teamId: Number,
    context: String,
    currentLabels: Array,
    resourceType: { type: String, default: "issue" },
    resourceId: Number,
  };

  connect() {
    this.currentFocusIndex = -1;
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;

    // Bind event handlers
    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    this.boundHandleEscape = this.handleEscape.bind(this);

    // Set up debounced filter
    this.filterDebounceTimeout = null;

    // Initialize filtered labels from rendered DOM
    this.updateFilteredLabels();
  }

  disconnect() {
    this.close();
  }

  open() {
    // Show picker
    this.pickerTarget.classList.remove("hidden");

    // Position overlay (for both card and sidebar contexts)
    this.positionOverlay();

    // Focus search input
    this.searchTarget.focus();

    // Add event listeners
    document.addEventListener("click", this.boundHandleClickOutside);
    document.addEventListener("keydown", this.boundHandleEscape);

    // Reset filtered labels
    this.updateFilteredLabels();
  }

  close() {
    this.pickerTarget.classList.add("hidden");
    this.searchTarget.value = "";
    this.currentFocusIndex = -1;

    // Remove event listeners
    document.removeEventListener("click", this.boundHandleClickOutside);
    document.removeEventListener("keydown", this.boundHandleEscape);
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close();
    }
  }

  handleEscape(event) {
    if (event.key === "Escape") {
      this.close();
    }
  }

  updateFilteredLabels() {
    this.filteredLabels = Array.from(this.labelListTarget.querySelectorAll(".label-option"));
    this.updateEmptyState();
  }

  filterLabels() {
    // Clear previous debounce timeout
    if (this.filterDebounceTimeout) {
      clearTimeout(this.filterDebounceTimeout);
    }

    // Debounce the filtering
    this.filterDebounceTimeout = setTimeout(() => {
      const query = this.searchTarget.value.trim().toLowerCase();

      if (query === "") {
        // Show all labels
        this.filteredLabels.forEach((el) => el.classList.remove("hidden"));
        this.createOptionTarget.classList.add("hidden");
        this.updateEmptyState();
        return;
      }

      // Filter labels
      let visibleCount = 0;
      let exactMatch = false;

      this.filteredLabels.forEach((el) => {
        const name = el.dataset.labelName.toLowerCase();
        if (name.includes(query)) {
          el.classList.remove("hidden");
          visibleCount++;
          if (name === query) {
            exactMatch = true;
          }
        } else {
          el.classList.add("hidden");
        }
      });

      // Show create option if no exact match
      if (!exactMatch && query.length > 0) {
        this.createTextTarget.textContent = query;
        this.createOptionTarget.classList.remove("hidden");
      } else {
        this.createOptionTarget.classList.add("hidden");
      }

      this.updateEmptyState();
      this.currentFocusIndex = -1;
    }, 300);
  }

  handleKeyDown(event) {
    // Don't interfere with normal typing
    if (!["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) {
      return;
    }

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
        this.close();
        break;
    }
  }

  focusNext() {
    const visibleOptions = this.getVisibleOptions();
    if (visibleOptions.length === 0) return;

    this.currentFocusIndex++;
    if (this.currentFocusIndex >= visibleOptions.length) {
      this.currentFocusIndex = 0;
    }

    this.updateVisualFocus(visibleOptions);
  }

  focusPrevious() {
    const visibleOptions = this.getVisibleOptions();
    if (visibleOptions.length === 0) return;

    this.currentFocusIndex--;
    if (this.currentFocusIndex < 0) {
      this.currentFocusIndex = visibleOptions.length - 1;
    }

    this.updateVisualFocus(visibleOptions);
  }

  getVisibleOptions() {
    const options = [];

    // Include create option if visible
    if (!this.createOptionTarget.classList.contains("hidden")) {
      options.push({ type: "create", element: this.createButtonTarget });
    }

    // Include visible label options
    this.filteredLabels.forEach((el) => {
      if (!el.classList.contains("hidden")) {
        options.push({ type: "label", element: el });
      }
    });

    return options;
  }

  updateVisualFocus(visibleOptions) {
    // Remove focus from all
    visibleOptions.forEach((option) => {
      option.element.classList.remove("bg-hover-highlight");
    });

    // Add focus to current
    if (this.currentFocusIndex >= 0 && this.currentFocusIndex < visibleOptions.length) {
      const focused = visibleOptions[this.currentFocusIndex];
      focused.element.classList.add("bg-hover-highlight");
      focused.element.scrollIntoView({ block: "nearest" });
    }
  }

  selectFocused() {
    const visibleOptions = this.getVisibleOptions();
    if (this.currentFocusIndex < 0 || this.currentFocusIndex >= visibleOptions.length) return;

    const focused = visibleOptions[this.currentFocusIndex];

    if (focused.type === "create") {
      this.createAndToggleLabel();
    } else {
      const checkbox = focused.element.querySelector("input[type=checkbox]");
      checkbox.checked = !checkbox.checked;
      this.toggleLabel({ target: checkbox });
    }
  }

  async toggleLabel(event) {
    const checkbox = event.target;
    const labelOption = checkbox.closest(".label-option");
    const labelId = parseInt(labelOption.dataset.labelId);
    const isChecked = checkbox.checked;

    try {
      if (isChecked) {
        await this.addLabelToIssue(labelId);
      } else {
        await this.removeLabelFromIssue(labelId);
      }
    } catch (error) {
      // Revert checkbox on error
      checkbox.checked = !isChecked;
      console.error("Failed to toggle label:", error);
    }
  }

  get labelBasePath() {
    const id = this.hasResourceIdValue ? this.resourceIdValue : this.issueIdValue;
    if (this.resourceTypeValue === "project") {
      return `/teams/${this.teamIdValue}/projects/${id}/project_labels`;
    }
    return `/teams/${this.teamIdValue}/issues/${id}/issue_labels`;
  }

  async addLabelToIssue(labelId) {
    const response = await fetch(this.labelBasePath, {
      method: "POST",
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken,
      },
      body: JSON.stringify({ label_id: labelId }),
    });

    if (!response.ok) {
      throw new Error("Failed to add label");
    }

    const html = await response.text();
    Turbo.renderStreamMessage(html);

    this.currentLabelsValue = [...this.currentLabelsValue, labelId];
  }

  async removeLabelFromIssue(labelId) {
    const response = await fetch(`${this.labelBasePath}/${labelId}`, {
      method: "DELETE",
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": this.csrfToken,
      },
    });

    if (!response.ok) {
      throw new Error("Failed to remove label");
    }

    const html = await response.text();
    Turbo.renderStreamMessage(html);

    this.currentLabelsValue = this.currentLabelsValue.filter((id) => id !== labelId);
  }

  async createAndToggleLabel() {
    const name = this.searchTarget.value.trim();
    if (!name) return;

    try {
      const response = await fetch(`/teams/${this.teamIdValue}/labels`, {
        method: "POST",
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify({
          label: {
            name: name,
            color: this.randomColor(),
          },
        }),
      });

      if (response.ok) {
        const html = await response.text();
        Turbo.renderStreamMessage(html);

        // Get the created label ID from the response
        // We'll need to extract this from the Turbo Stream response
        // For now, we'll wait a bit and then find the label by name
        setTimeout(() => {
          const newLabelElement = Array.from(
            this.labelListTarget.querySelectorAll(".label-option")
          ).find((el) => el.dataset.labelName === name);

          if (newLabelElement) {
            const labelId = parseInt(newLabelElement.dataset.labelId);
            const checkbox = newLabelElement.querySelector("input[type=checkbox]");
            checkbox.checked = true;

            // Add label to issue
            this.addLabelToIssue(labelId);
          }

          // Clear search
          this.searchTarget.value = "";
          this.filterLabels();
          this.updateFilteredLabels();
        }, 100);
      } else {
        const error = await response.text();
        console.error("Failed to create label:", error);
      }
    } catch (error) {
      console.error("Failed to create label:", error);
    }
  }

  randomColor() {
    const colors = ["#ef4444", "#f59e0b", "#10b981", "#3b82f6", "#8b5cf6", "#ec4899"];
    return colors[Math.floor(Math.random() * colors.length)];
  }

  positionOverlay() {
    const overlayWidth = 320; // w-80 = 20rem = 320px
    const overlayHeight = 400; // approximate
    let referenceElement = null;
    let rect = null;

    if (this.contextValue === "card") {
      // For card context, find the hovered card
      referenceElement = this.element.closest('[data-hovered="true"]');
      if (!referenceElement) return;
      rect = referenceElement.getBoundingClientRect();

      // Check if this is a wide element (like a list view row)
      // If the element is wider than 800px, it's probably a list row
      const isWideElement = rect.width > 800;

      let top = rect.top;
      let left;

      if (isWideElement) {
        // For list view: center the picker horizontally on screen
        left = (window.innerWidth - overlayWidth) / 2;
      } else {
        // For board view: position to the left of the card
        left = rect.left - overlayWidth - 8; // 8px gap

        // If it would go off the left edge, position to the right instead
        if (left < 8) {
          left = rect.right + 8;
        }

        // If still off-screen to the right, center it
        if (left + overlayWidth > window.innerWidth - 8) {
          left = (window.innerWidth - overlayWidth) / 2;
        }
      }

      // Check if overlay would go off-screen vertically
      if (top + overlayHeight > window.innerHeight) {
        top = window.innerHeight - overlayHeight - 8;
      }
      if (top < 8) {
        top = 8;
      }

      this.pickerTarget.style.top = `${top}px`;
      this.pickerTarget.style.left = `${left}px`;
    } else {
      // For sidebar context, find the labels dropdown button
      referenceElement = this.element.closest('[data-issue-sidebar-target="labelsDropdown"]') ||
                         this.element.closest('[data-project-sidebar-target="labelsDropdown"]');
      if (!referenceElement) return;

      // Get the button that triggers the dropdown
      const button = referenceElement.previousElementSibling;
      if (button) {
        rect = button.getBoundingClientRect();
      } else {
        rect = referenceElement.getBoundingClientRect();
      }

      // Position to the left of the reference element
      let top = rect.top;
      let left = rect.left - overlayWidth - 8; // 8px gap

      // If it would go off the left edge, position to the right instead
      if (left < 8) {
        left = rect.right + 8;
      }

      // Check if overlay would go off-screen vertically
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

  updateEmptyState() {
    const hasVisibleLabels = this.filteredLabels.some((el) => !el.classList.contains("hidden"));
    const createVisible = !this.createOptionTarget.classList.contains("hidden");

    if (!hasVisibleLabels && !createVisible) {
      this.emptyStateTarget.classList.remove("hidden");
    } else {
      this.emptyStateTarget.classList.add("hidden");
    }
  }
}
