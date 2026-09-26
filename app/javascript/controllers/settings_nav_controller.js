import { Controller } from "@hotwired/stimulus";

// Two-column settings layout: clicking a section link shows its panel and
// records the section in the URL so refreshes and redirects land back on it.
export default class extends Controller {
  static targets = ["link", "panel"];
  static classes = ["active", "inactive"];

  select(event) {
    event.preventDefault();
    this.show(event.currentTarget.dataset.section);
  }

  show(section) {
    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.section !== section);
    });
    this.linkTargets.forEach((link) => {
      const active = link.dataset.section === section;
      link.classList.remove(...(active ? this.inactiveClasses : this.activeClasses));
      link.classList.add(...(active ? this.activeClasses : this.inactiveClasses));
    });

    const url = new URL(window.location.href);
    url.searchParams.set("section", section);
    window.history.replaceState(window.history.state, "", url);
  }
}
