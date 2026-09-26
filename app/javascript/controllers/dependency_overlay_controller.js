import { Controller } from "@hotwired/stimulus";
import { ConnectorLayer } from "lib/dependency_connectors";

const HOVERED_CLASSES = ["ring-2", "ring-accent", "rounded"];
const NEIGHBOR_CLASSES = ["ring-1", "ring-accent/60", "rounded"];
// Same-column links bow about 3/4 of this into the gutter, so it stays inside the board's
// gap-3 (12px) column spacing instead of the board widening to make room.
const SAME_COLUMN_BOW = 12;

// Board "Dependencies" overlay: draws a line for every link between two rendered cards and
// keeps them attached while the board, its columns, or the window move underneath. Hovering a
// card dims unrelated lines; clicking a linked card opens its dependency map.
export default class extends Controller {
  static values = { edges: Array };

  connect() {
    this.layer = new ConnectorLayer(this.element, { sameColumnBow: SAME_COLUMN_BOW });
    this.hoveredId = null;
    this.neighbors = this.buildNeighbors();

    this.scheduleRedraw = this.scheduleRedraw.bind(this);
    this.onMouseOver = this.onMouseOver.bind(this);
    this.onMouseOut = this.onMouseOut.bind(this);
    this.onClick = this.onClick.bind(this);

    // Capture catches the board's own scroll and each column's independent vertical scroll.
    this.element.addEventListener("scroll", this.scheduleRedraw, { capture: true, passive: true });
    this.element.addEventListener("mouseover", this.onMouseOver);
    this.element.addEventListener("mouseout", this.onMouseOut);
    this.element.addEventListener("click", this.onClick);
    document.addEventListener("turbo:frame-render", this.scheduleRedraw);

    this.resizeObserver = new ResizeObserver(this.scheduleRedraw);
    this.resizeObserver.observe(this.element);

    // Cards move between columns (drag, pickers) via turbo streams without resizing the board.
    this.mutationObserver = new MutationObserver((records) => {
      if (records.some((record) => !this.layer.svg.contains(record.target))) this.scheduleRedraw();
    });
    this.mutationObserver.observe(this.element, { childList: true, subtree: true });

    this.scheduleRedraw();
    this.legend?.classList.remove("hidden");
  }

  disconnect() {
    this.legend?.classList.add("hidden");
    cancelAnimationFrame(this.frame);
    this.element.removeEventListener("scroll", this.scheduleRedraw, { capture: true });
    this.element.removeEventListener("mouseover", this.onMouseOver);
    this.element.removeEventListener("mouseout", this.onMouseOut);
    this.element.removeEventListener("click", this.onClick);
    document.removeEventListener("turbo:frame-render", this.scheduleRedraw);
    this.resizeObserver.disconnect();
    this.mutationObserver.disconnect();
    this.setHovered(null);
    this.layer.destroy();
  }

  // The color key bar under the top bar (issues/index), outside the board frame.
  get legend() {
    return document.getElementById("dependency_legend");
  }

  scheduleRedraw() {
    if (this.frame) return;

    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.layer.draw(this.edgesValue, {
        nodeFor: (id) => this.element.querySelector(`#issue_${id}`),
        focusId: this.hoveredId,
      });
    });
  }

  // ── Hover ──────────────────────────────────────────────────────

  onMouseOver(event) {
    const card = event.target.closest("[data-issue-id]");
    if (card) this.setHovered(card.dataset.issueId);
  }

  onMouseOut(event) {
    const card = event.target.closest("[data-issue-id]");
    if (card && !card.contains(event.relatedTarget)) this.setHovered(null);
  }

  setHovered(id) {
    if (id === this.hoveredId) return;

    this.markCards(this.hoveredId, false);
    this.hoveredId = id;
    this.markCards(id, true);

    this.layer.highlight(id);
    // Redraw so the hovered card's incoming blocker lines pick up the "blocked by" color.
    this.scheduleRedraw();
  }

  markCards(id, on) {
    if (id == null) return;

    setClasses(this.cardFor(id), HOVERED_CLASSES, on);
    for (const neighborId of this.neighbors.get(id) || []) {
      setClasses(this.cardFor(neighborId), NEIGHBOR_CLASSES, on);
    }
  }

  cardFor(id) {
    return this.element.querySelector(`#issue_${id}`);
  }

  buildNeighbors() {
    const neighbors = new Map();
    const link = (a, b) => {
      if (!neighbors.has(a)) neighbors.set(a, new Set());
      neighbors.get(a).add(b);
    };
    for (const edge of this.edgesValue) {
      link(String(edge.from_id), String(edge.to_id));
      link(String(edge.to_id), String(edge.from_id));
    }
    return neighbors;
  }

  // ── Click-through ──────────────────────────────────────────────

  // Only cards with at least one line carry data-dependency-map-url; the rest keep their
  // normal link to the issue. Modified clicks (new tab, etc.) are left alone too.
  onClick(event) {
    if (event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    const card = event.target.closest("[data-dependency-map-url]");
    const link = event.target.closest("a");
    if (!card || !link || link.parentElement !== card) return;

    event.preventDefault();
    window.Turbo.visit(card.dataset.dependencyMapUrl);
  }
}

function setClasses(element, classes, on) {
  if (!element) return;
  if (on) element.classList.add(...classes);
  else element.classList.remove(...classes);
}
