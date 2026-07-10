import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "search",
    "channelList",
    "emptyState",
    "form",
    "channelIdInput",
    "channelNameInput",
    "integrationIdInput",
  ];

  static values = {
    channelsUrl: String,
  };

  connect() {
    this.currentFocusIndex = -1;
    this.filterDebounceTimeout = null;

    if (this.hasSearchTarget) {
      requestAnimationFrame(() => this.searchTarget.focus());
    }

    this.boundBackdropClick = this.backdropClick.bind(this);
    this.element.addEventListener("click", this.boundBackdropClick);
  }

  disconnect() {
    this.element.removeEventListener("click", this.boundBackdropClick);
    if (this.filterDebounceTimeout) clearTimeout(this.filterDebounceTimeout);
  }

  stopPropagation(event) {
    event.stopPropagation();
  }

  backdropClick(event) {
    if (event.target === this.element) {
      this.close();
    }
  }

  close() {
    this.element.remove();
  }

  filter() {
    if (this.filterDebounceTimeout) clearTimeout(this.filterDebounceTimeout);

    this.filterDebounceTimeout = setTimeout(() => {
      const query = this.searchTarget.value.trim().toLowerCase();
      const options = this.channelOptions();

      let visibleCount = 0;
      options.forEach((el) => {
        const haystack = el.dataset.channelSearch || "";
        if (query === "" || haystack.includes(query)) {
          el.classList.remove("hidden");
          visibleCount++;
        } else {
          el.classList.add("hidden");
        }
      });

      if (this.hasEmptyStateTarget) {
        this.emptyStateTarget.classList.toggle("hidden", visibleCount > 0);
      }
      this.currentFocusIndex = -1;
      this.refreshFocus();
    }, 200);
  }

  handleKeyDown(event) {
    if (!["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) return;

    if (event.key === "Escape") {
      event.preventDefault();
      this.close();
      return;
    }

    const visible = this.visibleOptions();
    if (visible.length === 0) return;

    event.preventDefault();

    if (event.key === "ArrowDown") {
      this.currentFocusIndex = Math.min(this.currentFocusIndex + 1, visible.length - 1);
      this.refreshFocus();
    } else if (event.key === "ArrowUp") {
      this.currentFocusIndex = Math.max(this.currentFocusIndex - 1, 0);
      this.refreshFocus();
    } else if (event.key === "Enter") {
      const idx = this.currentFocusIndex >= 0 ? this.currentFocusIndex : 0;
      visible[idx].click();
    }
  }

  select(event) {
    const button = event.currentTarget;
    const channelId = button.dataset.channelId;
    const channelName = button.dataset.channelName;

    this.channelIdInputTarget.value = channelId;
    this.channelNameInputTarget.value = channelName;
    if (this.hasIntegrationIdInputTarget) {
      this.integrationIdInputTarget.value = button.dataset.integrationId || "";
    }
    this.formTarget.requestSubmit();
  }

  channelOptions() {
    return Array.from(this.channelListTarget.querySelectorAll(".channel-option"));
  }

  visibleOptions() {
    return this.channelOptions().filter((el) => !el.classList.contains("hidden"));
  }

  refreshFocus() {
    const visible = this.visibleOptions();
    visible.forEach((el, i) => {
      if (i === this.currentFocusIndex) {
        el.classList.add("bg-hover-highlight");
        el.scrollIntoView({ block: "nearest" });
      } else {
        el.classList.remove("bg-hover-highlight");
      }
    });
  }
}
