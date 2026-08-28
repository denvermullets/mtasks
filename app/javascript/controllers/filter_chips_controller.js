import { Controller } from "@hotwired/stimulus";

const TYPE_LABELS = {
  lane_ids: "Status",
  assignee_ids: "Assignee",
  creator_ids: "Created by",
  priority: "Priority",
  label_ids: "Labels",
  project_ids: "Project",
};

export default class extends Controller {
  static targets = ["container"];

  connect() {
    this.boundOnChange = this.onFiltersChanged.bind(this);
    document.addEventListener("filters:changed", this.boundOnChange);
  }

  disconnect() {
    document.removeEventListener("filters:changed", this.boundOnChange);
  }

  remove(event) {
    event.preventDefault();
    // No track() here. This dispatches filters:remove, which filter_menu#handleExternalRemove
    // routes into applyKeyChange — the single emitter for issue-filter/remove (§4.4). Adding a
    // call here would double-count every chip dismissal.
    const { filterKey, filterValue } = event.currentTarget.dataset;
    document.dispatchEvent(
      new CustomEvent("filters:remove", { detail: { key: filterKey, value: filterValue } })
    );
  }

  clearAll(event) {
    event.preventDefault();
    // No track() here either — this calls filter_menu#clearAll directly, which emits the clear.
    const menuEl = document.querySelector('[data-controller~="filter-menu"]');
    if (!menuEl) return;
    const menu = this.application.getControllerForElementAndIdentifier(menuEl, "filter-menu");
    if (menu) menu.clearAll();
  }

  onFiltersChanged(event) {
    this.render(event.detail || {});
  }

  render(detail) {
    const container = this.containerTarget;
    container.innerHTML = "";

    const order = ["lane_ids", "assignee_ids", "creator_ids", "priority", "label_ids", "project_ids"];
    let total = 0;

    order.forEach((key) => {
      const items = detail[key] || [];
      items.forEach((item) => {
        container.appendChild(this.buildChip(key, item.value, item.label));
        total += 1;
      });
    });

    if (total > 0) {
      container.appendChild(this.buildClearAll());
      container.classList.remove("hidden");
    } else {
      container.classList.add("hidden");
    }
  }

  buildChip(key, value, labelText) {
    const chip = document.createElement("span");
    chip.className =
      "inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-xs font-medium bg-foreground border border-stroke text-gray-400";

    const prefix = document.createElement("span");
    prefix.className = "text-gray-500";
    prefix.textContent = `${TYPE_LABELS[key] || key}:`;
    chip.appendChild(prefix);

    const label = document.createElement("span");
    label.className = "truncate max-w-[8rem] text-gray-300";
    label.textContent = labelText || value;
    chip.appendChild(label);

    const button = document.createElement("button");
    button.type = "button";
    button.className = "ml-0.5 text-gray-500 hover:text-accent transition-colors cursor-pointer";
    button.setAttribute("aria-label", "Remove filter");
    button.dataset.action = "click->filter-chips#remove";
    button.dataset.filterKey = key;
    button.dataset.filterValue = value;
    button.innerHTML =
      '<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12"></path></svg>';
    chip.appendChild(button);

    return chip;
  }

  buildClearAll() {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "ml-1 text-xs text-gray-500 hover:text-accent transition-colors cursor-pointer";
    button.dataset.action = "click->filter-chips#clearAll";
    button.textContent = "Clear all";
    return button;
  }
}
