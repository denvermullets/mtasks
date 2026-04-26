import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button", "panel", "badge", "rootView", "typeView", "typeCount", "clearAllRow"];

  connect() {
    this.boundClickOutside = this.handleClickOutside.bind(this);
    this.boundExternalRemove = this.handleExternalRemove.bind(this);
    document.addEventListener("click", this.boundClickOutside);
    document.addEventListener("filters:remove", this.boundExternalRemove);
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside);
    document.removeEventListener("filters:remove", this.boundExternalRemove);
  }

  togglePanel(event) {
    event.stopPropagation();
    this.panelTarget.classList.toggle("hidden");
    if (!this.panelTarget.classList.contains("hidden")) this.showRoot();
  }

  closePanel() {
    this.panelTarget.classList.add("hidden");
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) this.closePanel();
  }

  showType(event) {
    const type = event.currentTarget.dataset.filterType;
    this.rootViewTarget.classList.add("hidden");
    this.typeViewTargets.forEach((view) => {
      view.classList.toggle("hidden", view.dataset.filterType !== type);
      view.classList.toggle("flex", view.dataset.filterType === type);
    });
  }

  showRoot() {
    this.rootViewTarget.classList.remove("hidden");
    this.typeViewTargets.forEach((view) => {
      view.classList.add("hidden");
      view.classList.remove("flex");
    });
  }

  toggleFilter(event) {
    const key = event.currentTarget.dataset.filterKey;
    this.applyKeyChange(key);
  }

  clearAll() {
    this.element.querySelectorAll('input[type="checkbox"]').forEach((cb) => (cb.checked = false));
    const url = new URL(window.location.href);
    ["lane_ids", "assignee_ids", "creator_ids", "priority", "label_ids", "project_ids"].forEach((k) =>
      url.searchParams.delete(k)
    );
    this.commitUrl(url);
    this.refreshIndicators();
    this.dispatchChanged();
  }

  handleExternalRemove(event) {
    const { key, value } = event.detail || {};
    if (!key) return;
    const checkbox = this.element.querySelector(
      `input[data-filter-key="${key}"][value="${CSS.escape(String(value))}"]`
    );
    if (checkbox) checkbox.checked = false;
    this.applyKeyChange(key);
  }

  applyKeyChange(key) {
    const values = this.selectedValuesFor(key);
    const url = new URL(window.location.href);
    if (values.length > 0) {
      url.searchParams.set(key, values.join(","));
    } else {
      url.searchParams.delete(key);
    }
    this.commitUrl(url);
    this.refreshIndicators();
    this.dispatchChanged();
  }

  selectedValuesFor(key) {
    return Array.from(
      this.element.querySelectorAll(`input[data-filter-key="${key}"]:checked`)
    ).map((cb) => cb.value);
  }

  selectedLabelsFor(key) {
    return Array.from(
      this.element.querySelectorAll(`input[data-filter-key="${key}"]:checked`)
    ).map((cb) => ({ value: cb.value, label: cb.dataset.filterLabel }));
  }

  commitUrl(url) {
    window.history.pushState({}, "", url.toString());
    clearTimeout(this.refreshTimeout);
    this.refreshTimeout = setTimeout(() => {
      window.Turbo.visit(url.toString(), { frame: "issues_board" });
    }, 150);
  }

  refreshIndicators() {
    const totals = {};
    let total = 0;
    this.element.querySelectorAll("input[data-filter-key]:checked").forEach((cb) => {
      const k = cb.dataset.filterKey;
      totals[k] = (totals[k] || 0) + 1;
      total += 1;
    });

    this.typeCountTargets.forEach((el) => {
      const k = el.dataset.filterType;
      const n = totals[k] || 0;
      if (n > 0) {
        el.textContent = n;
        el.classList.remove("hidden");
      } else {
        el.textContent = "";
        el.classList.add("hidden");
      }
    });

    if (this.hasBadgeTarget) {
      if (total > 0) {
        this.badgeTarget.textContent = `Filter · ${total}`;
        this.badgeTarget.classList.remove("hidden");
      } else {
        this.badgeTarget.textContent = "";
        this.badgeTarget.classList.add("hidden");
      }
    }

    if (this.hasButtonTarget) {
      this.buttonTarget.classList.toggle("border-accent", total > 0);
      this.buttonTarget.classList.toggle("text-gray-100", total > 0);
      this.buttonTarget.classList.toggle("border-stroke", total === 0);
    }

    if (this.hasClearAllRowTarget) {
      this.clearAllRowTarget.classList.toggle("hidden", total === 0);
    }
  }

  dispatchChanged() {
    const detail = {
      lane_ids: this.selectedLabelsFor("lane_ids"),
      assignee_ids: this.selectedLabelsFor("assignee_ids"),
      creator_ids: this.selectedLabelsFor("creator_ids"),
      priority: this.selectedLabelsFor("priority"),
      label_ids: this.selectedLabelsFor("label_ids"),
      project_ids: this.selectedLabelsFor("project_ids"),
    };
    document.dispatchEvent(new CustomEvent("filters:changed", { detail }));
  }
}
