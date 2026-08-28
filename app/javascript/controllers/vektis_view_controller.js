import { Controller } from "@hotwired/stimulus";
import { trackEngagement } from "vektis";

// Emits feature.engagement / view for the read-only surfaces that have no interaction to hang an
// event on. Taxonomy §9 splits three features by action: the server owns their mutations, the
// browser owns the fact that someone looked at the page. project-management and roadmap are two of
// those three; the third, issue-attachment, has a real handler in lightbox_controller.
//
// Driven entirely by data attributes so the ERB names the feature. There is deliberately no slug
// allowlist here: adding one is an edit to the taxonomy doc plus a data attribute, not to this file.
//
// Turbo Drive connects this twice per navigation — it renders a cached snapshot ("preview") first
// and the real response second, on two different controller instances. Two guards, because they
// fail in different directions:
//   - data-turbo-preview on <html> is Turbo's own marker for "this render is a placeholder"; a
//     placeholder that may yet be replaced by a 404 is not a page view.
//   - lastViewKey catches every other re-render of the same URL: a turbo-stream broadcast that
//     replaces this element, a restoration visit, a plain reconnect. Module scope, not instance
//     state, since the duplicate is a different instance. Navigating away and back changes the key
//     in between, so a genuine second view of the same page still counts.
let lastViewKey = null;

export default class extends Controller {
  static values = { featureId: String, surface: String, tab: String };

  connect() {
    if (!this.featureIdValue) return;
    if (document.documentElement.hasAttribute("data-turbo-preview")) return;

    const key = `${this.featureIdValue}|${window.location.pathname}${window.location.search}`;
    if (key === lastViewKey) return;
    lastViewKey = key;

    // Optional keys are omitted rather than sent empty — the registry (§5.2) is a closed set of
    // enum values and "" is not one of them.
    const properties = {};
    if (this.surfaceValue) properties.surface = this.surfaceValue;
    if (this.tabValue) properties.tab = this.tabValue;

    trackEngagement(this.featureIdValue, "view", properties);
  }
}
