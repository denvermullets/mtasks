// Draws curved, colored connector lines between DOM cards inside a container.
// Shared by the board dependency overlay and the dependency map page; callers
// decide which edges to draw and when to redraw (e.g. on resize).
//
//   const layer = new ConnectorLayer(containerEl, { sameColumnBow })  // bow is optional
//   layer.draw(edges, { nodeFor: id => el, focusId })
//   layer.highlight(id)  // dim edges not touching id; null resets

const SVG_NS = "http://www.w3.org/2000/svg"

const MIN_CONTROL_OFFSET = 40
const SAME_COLUMN_BOW = 28 // horizontal control offset when both anchors sit on the left edge
const COLUMN_TOLERANCE = 12 // px of horizontal overlap still treated as "beside", not "same column"
const SOURCE_DOT_RADIUS = 4
const TARGET_RING_RADIUS = 6

const KIND_COLORS = {
  blocks: "var(--dep-blocks)",
  relates: "var(--dep-relates)",
  duplicates: "var(--dep-duplicates)"
}
const BLOCKED_BY_COLOR = "var(--dep-blocked-by)"

export class ConnectorLayer {
  constructor(container, { sameColumnBow = SAME_COLUMN_BOW } = {}) {
    this.container = container
    this.sameColumnBow = sameColumnBow
    this.highlightedId = null

    if (getComputedStyle(container).position === "static") {
      container.style.position = "relative"
    }

    this.svg = document.createElementNS(SVG_NS, "svg")
    this.svg.setAttribute("class", "absolute inset-0 pointer-events-none overflow-visible z-10")
    this.svg.setAttribute("aria-hidden", "true")
    container.appendChild(this.svg)
  }

  draw(edges, { nodeFor, focusId = null } = {}) {
    // Collapse the SVG first so it never props up the container's scroll size.
    this.svg.setAttribute("width", 0)
    this.svg.setAttribute("height", 0)

    // Read phase: every rect up front, no DOM writes in between.
    const origin = this.containerOrigin()
    const width = this.container.scrollWidth
    const height = this.container.scrollHeight
    const rects = new Map()
    const rectFor = (id) => {
      if (!rects.has(id)) {
        const node = nodeFor(id)
        rects.set(id, node ? this.relativeRect(node, origin) : null)
      }
      return rects.get(id)
    }

    const measured = []
    for (const edge of edges) {
      const source = rectFor(edge.from_id)
      const target = rectFor(edge.to_id)
      if (source && target) measured.push({ edge, source, target })
    }

    // Write phase: build everything off-DOM, then swap in one go.
    const groups = measured.map(({ edge, source, target }) =>
      this.buildEdge(edge, source, target, focusId)
    )
    this.svg.setAttribute("width", width)
    this.svg.setAttribute("height", height)
    this.svg.replaceChildren(...groups)
    this.applyHighlight()
  }

  highlight(issueId) {
    this.highlightedId = issueId == null ? null : String(issueId)
    this.applyHighlight()
  }

  clear() {
    this.svg.replaceChildren()
  }

  destroy() {
    this.svg.remove()
  }

  // ── Geometry ───────────────────────────────────────────────────

  containerOrigin() {
    const rect = this.container.getBoundingClientRect()
    return {
      x: rect.left + this.container.clientLeft - this.container.scrollLeft,
      y: rect.top + this.container.clientTop - this.container.scrollTop
    }
  }

  relativeRect(node, origin) {
    const rect = node.getBoundingClientRect()
    const left = rect.left - origin.x
    const top = rect.top - origin.y
    return { left, top, right: left + rect.width, midY: top + rect.height / 2 }
  }

  // Returns anchor points, bezier control points, and which way the line
  // travels as it arrives at the target (for the chevron).
  route(source, target) {
    const y1 = source.midY
    const y2 = target.midY

    if (target.left >= source.right - COLUMN_TOLERANCE) {
      const x1 = source.right
      const x2 = target.left
      const offset = Math.max(MIN_CONTROL_OFFSET, Math.abs(x2 - x1) / 2)
      return { x1, y1, x2, y2, cx1: x1 + offset, cx2: x2 - offset, arrivesRightward: true }
    }

    if (target.right <= source.left + COLUMN_TOLERANCE) {
      const x1 = source.left
      const x2 = target.right
      const offset = Math.max(MIN_CONTROL_OFFSET, Math.abs(x2 - x1) / 2)
      return { x1, y1, x2, y2, cx1: x1 - offset, cx2: x2 + offset, arrivesRightward: false }
    }

    // Same column: both anchors on the left edge, bowing out into the gutter.
    const x1 = source.left
    const x2 = target.left
    const bow = Math.min(x1, x2) - this.sameColumnBow
    return { x1, y1, x2, y2, cx1: bow, cx2: bow, arrivesRightward: true }
  }

  // ── SVG building ───────────────────────────────────────────────

  buildEdge(edge, source, target, focusId) {
    const { x1, y1, x2, y2, cx1, cx2, arrivesRightward } = this.route(source, target)
    const color = this.colorFor(edge, focusId)

    const group = svgEl("g", {
      class: "dep-edge",
      "data-from": edge.from_id,
      "data-to": edge.to_id,
      "data-kind": edge.kind
    })
    group.style.color = color

    const path = svgEl("path", {
      d: `M ${x1} ${y1} C ${cx1} ${y1}, ${cx2} ${y2}, ${x2} ${y2}`,
      fill: "none",
      stroke: "currentColor",
      "stroke-width": 2,
      "stroke-linecap": "round"
    })
    if (edge.kind === "duplicates") path.setAttribute("stroke-dasharray", "5 5")

    const dot = svgEl("circle", { cx: x1, cy: y1, r: SOURCE_DOT_RADIUS, fill: "currentColor" })

    const ring = svgEl("circle", {
      cx: x2,
      cy: y2,
      r: TARGET_RING_RADIUS,
      stroke: "currentColor",
      "stroke-width": 1.5
    })
    ring.style.fill = "var(--color-foreground)"

    const chevron = svgEl("path", {
      d: "M -1.25 -2.5 L 1.5 0 L -1.25 2.5",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": 1.5,
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      transform: `translate(${x2} ${y2})${arrivesRightward ? "" : " rotate(180)"}`
    })

    group.append(path, dot, ring, chevron)
    return group
  }

  colorFor(edge, focusId) {
    if (focusId != null && String(edge.to_id) === String(focusId) && edge.kind === "blocks") {
      return BLOCKED_BY_COLOR
    }
    return KIND_COLORS[edge.kind] || KIND_COLORS.blocks
  }

  applyHighlight() {
    const id = this.highlightedId
    for (const group of this.svg.children) {
      const touches = id === null || group.dataset.from === id || group.dataset.to === id
      group.classList.toggle("is-dimmed", !touches)
    }
  }
}

function svgEl(tag, attrs) {
  const el = document.createElementNS(SVG_NS, tag)
  for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value)
  return el
}
