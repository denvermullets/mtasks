import { Controller } from "@hotwired/stimulus";
import { ConnectorLayer } from "lib/dependency_connectors";

// Dependency map page: draws the blocks lines between the depth columns and keeps them attached
// as the graph resizes or scrolls. Hovering a node dims every line that doesn't touch it.
export default class extends Controller {
  static values = { edges: Array, focusId: Number };

  connect() {
    this.layer = new ConnectorLayer(this.element);
    this.scheduleRedraw = this.scheduleRedraw.bind(this);

    this.element.addEventListener("scroll", this.scheduleRedraw, { passive: true });
    this.resizeObserver = new ResizeObserver(this.scheduleRedraw);
    this.resizeObserver.observe(this.element);
    // Late-loading fonts reflow card heights without resizing the graph box.
    document.fonts?.ready.then(this.scheduleRedraw);

    this.centerFocus();
    this.scheduleRedraw();
  }

  disconnect() {
    cancelAnimationFrame(this.frame);
    this.element.removeEventListener("scroll", this.scheduleRedraw);
    this.resizeObserver.disconnect();
    this.layer.destroy();
  }

  scheduleRedraw() {
    if (this.frame) return;

    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.layer.draw(this.edgesValue, {
        nodeFor: (id) => this.element.querySelector(`#dep_node_${id}`),
        focusId: this.focusIdValue,
      });
    });
  }

  // On narrow screens the graph scrolls sideways; start with the selected issue in view.
  centerFocus() {
    const focus = this.element.querySelector(`#dep_node_${this.focusIdValue}`);
    if (!focus || this.element.scrollWidth <= this.element.clientWidth) return;

    this.element.scrollLeft = focus.offsetLeft - (this.element.clientWidth - focus.offsetWidth) / 2;
  }

  hover(event) {
    this.layer.highlight(event.currentTarget.dataset.issueId);
  }

  unhover() {
    this.layer.highlight(null);
  }
}
