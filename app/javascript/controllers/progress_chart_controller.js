import { Controller } from "@hotwired/stimulus"

const SERIES = [
  { key: "scope", label: "Scope", color: "#8b93a7", fillOpacity: 0.22 },
  { key: "started", label: "Started", color: "#f5c04a", fillOpacity: 0.22 },
  { key: "completed", label: "Completed", color: "#5eead4", fillOpacity: 0.3, glow: true }
]
const EXPECTED_COLOR = "#f87171"

export default class extends Controller {
  static values = {
    data: Array,
    expected: Array,
    behindSchedule: Boolean,
    mini: { type: Boolean, default: false }
  }

  connect() {
    this.render()
  }

  render() {
    const data = this.dataValue
    if (!data || data.length === 0) {
      this.element.innerHTML = '<span class="text-xs text-gray-600">No data yet</span>'
      return
    }

    if (this.miniValue) {
      this.renderMini(data)
    } else {
      this.renderFull(data)
    }
  }

  renderFull(data) {
    const width = 960
    const height = 270
    const padding = { top: 16, right: 52, bottom: 30, left: 32 }
    const chartW = width - padding.left - padding.right
    const chartH = height - padding.top - padding.bottom
    const uid = Math.random().toString(36).slice(2, 8)

    const expected = this.expectedValue || []
    const hasExpected = expected.length >= 2 && expected.length === data.length
    const { max: maxVal, ticks } = this.niceScale(Math.max(
      ...data.map(d => d.scope),
      ...(hasExpected ? expected.map(d => d.value) : []),
      1
    ))

    const xScale = (i) => padding.left + (i / (data.length - 1 || 1)) * chartW
    const yScale = (v) => padding.top + chartH - (v / maxVal) * chartH
    const baseline = yScale(0)
    const pointsFor = (key) => data.map((d, i) => [xScale(i), yScale(d[key])])

    const series = SERIES.map(s => ({ ...s, points: pointsFor(s.key), last: data[data.length - 1][s.key] }))

    const gradients = series.map(s => `
      <linearGradient id="pc-${s.key}-${uid}" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="${s.color}" stop-opacity="${s.fillOpacity}" />
        <stop offset="100%" stop-color="${s.color}" stop-opacity="0.02" />
      </linearGradient>`).join('')

    const areas = series.map(s =>
      `<path d="${this.areaPath(s.points, baseline)}" fill="url(#pc-${s.key}-${uid})" />`).join('')

    const lines = series.map(s => `
      <path d="${this.smoothPath(s.points)}" fill="none" stroke="${s.color}" stroke-width="2"
        stroke-linejoin="round" stroke-linecap="round" ${s.glow ? `filter="url(#pc-glow-${uid})"` : ''} />`).join('')

    // Expected progress line — piecewise so it steps when scope changes
    const expectedLine = hasExpected
      ? `<path d="${this.linePath(expected.map((p, i) => [xScale(i), yScale(p.value)]))}" fill="none"
          stroke="${EXPECTED_COLOR}" stroke-width="2" stroke-dasharray="7,5" stroke-linecap="round" />`
      : ""

    const endX = xScale(data.length - 1)
    const endDots = series.map(s => `
      <circle cx="${endX}" cy="${yScale(s.last)}" r="4.5" fill="${s.color}" class="stroke-background" stroke-width="2" />`).join('')
    const endLabels = this.spreadLabels(series.map(s => ({ ...s, y: yScale(s.last) })), 20, padding.top + 8, baseline)
      .map(s => `
        <g transform="translate(${endX + 10}, ${s.labelY})">
          <rect x="0" y="-10" width="${this.badgeWidth(s.last)}" height="20" rx="4"
            fill="${s.color}" fill-opacity="0.14" />
          <text x="${this.badgeWidth(s.last) / 2}" y="4" text-anchor="middle" class="fill-gray-100"
            font-size="11" font-weight="600">${s.last}</text>
        </g>`).join('')

    const legend = series.map(s => `
      <div class="flex items-center gap-2.5 rounded-lg border border-gray-800 bg-gray-900/60 pl-3 pr-1.5 py-1.5">
        <span class="w-2.5 h-2.5 rounded-full" style="background: ${s.color}"></span>
        <span class="text-gray-300">${s.label}</span>
        <span class="ml-2 rounded-md bg-gray-800 px-2 py-0.5 font-semibold text-gray-100">${s.last}</span>
      </div>`).join('')

    const behind = this.behindScheduleValue ? `
      <div class="ml-auto flex items-center gap-2 rounded-lg bg-red-500/10 px-3 py-1.5 text-red-400">
        <span class="w-2.5 h-2.5 rounded-full bg-red-400"></span>
        Behind schedule
      </div>` : ''

    this.element.innerHTML = `
      <div class="mb-4 flex flex-wrap items-center gap-2 text-xs">${legend}${behind}</div>
      <div class="relative" data-chart-wrapper>
        <svg viewBox="0 0 ${width} ${height}" class="w-full h-auto" style="font-family: inherit">
          <defs>
            ${gradients}
            <filter id="pc-glow-${uid}" x="-10%" y="-50%" width="120%" height="200%">
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
            </filter>
          </defs>

          ${ticks.map(v => `
            <line x1="${padding.left}" y1="${yScale(v)}" x2="${width - padding.right}" y2="${yScale(v)}"
              class="stroke-gray-700" stroke-width="${v === 0 ? 1 : 0.75}" ${v === 0 ? '' : 'stroke-dasharray="2,4"'} />
            <text x="${padding.left - 10}" y="${yScale(v) + 4}" text-anchor="end"
              class="fill-gray-500" font-size="11">${v}</text>
          `).join('')}
          <line x1="${padding.left}" y1="${padding.top}" x2="${padding.left}" y2="${baseline}"
            class="stroke-gray-700" stroke-width="1" />

          ${areas}
          ${lines}
          ${expectedLine}
          ${endDots}
          ${endLabels}

          <text x="${padding.left}" y="${height - 6}" text-anchor="middle" class="fill-gray-500" font-size="11">${this.formatDate(data[0].date)}</text>
          <text x="${endX}" y="${height - 6}" text-anchor="middle" class="fill-gray-500" font-size="11">${this.formatDate(data[data.length - 1].date)}</text>

          <g data-hover-layer style="display: none; pointer-events: none">
            <line data-hover-line y1="${padding.top}" y2="${baseline}" class="stroke-gray-400" stroke-width="1" stroke-dasharray="3,3" />
            ${series.map(s => `<circle data-hover-dot="${s.key}" r="4" fill="${s.color}" class="stroke-background" stroke-width="2" />`).join('')}
          </g>
          <rect data-hover-target x="${padding.left}" y="${padding.top}" width="${chartW}" height="${chartH}"
            fill="transparent" />
        </svg>
        <div data-hover-tooltip class="pointer-events-none absolute top-0 hidden rounded-lg border border-gray-700 bg-gray-900/95 px-3 py-2 text-xs shadow-lg"></div>
      </div>
    `

    this.bindHover({ data, series, expected: hasExpected ? expected : null, xScale, yScale, width })
  }

  bindHover({ data, series, expected, xScale, yScale, width }) {
    const wrapper = this.element.querySelector('[data-chart-wrapper]')
    const svg = wrapper.querySelector('svg')
    const target = svg.querySelector('[data-hover-target]')
    const layer = svg.querySelector('[data-hover-layer]')
    const line = svg.querySelector('[data-hover-line]')
    const tooltip = wrapper.querySelector('[data-hover-tooltip]')

    const show = (event) => {
      const rect = svg.getBoundingClientRect()
      const scale = rect.width / width
      const svgX = (event.clientX - rect.left) / scale
      const step = data.length > 1 ? xScale(1) - xScale(0) : 1
      const i = Math.max(0, Math.min(data.length - 1, Math.round((svgX - xScale(0)) / step)))
      const x = xScale(i)

      line.setAttribute('x1', x)
      line.setAttribute('x2', x)
      series.forEach(s => {
        const dot = layer.querySelector(`[data-hover-dot="${s.key}"]`)
        dot.setAttribute('cx', x)
        dot.setAttribute('cy', yScale(data[i][s.key]))
      })
      layer.style.display = ''

      const rows = series.map(s => this.tooltipRow(s.color, s.label, data[i][s.key]))
      if (expected) rows.push(this.tooltipRow(EXPECTED_COLOR, 'Expected', Math.round(expected[i].value)))
      tooltip.innerHTML = `<div class="mb-1 text-gray-400">${this.formatDate(data[i].date)}</div>${rows.join('')}`
      tooltip.classList.remove('hidden')

      const left = x * scale
      const flip = left > rect.width / 2
      tooltip.style.left = flip ? '' : `${left + 12}px`
      tooltip.style.right = flip ? `${rect.width - left + 12}px` : ''
      tooltip.style.top = '8px'
    }

    const hide = () => {
      layer.style.display = 'none'
      tooltip.classList.add('hidden')
    }

    target.addEventListener('pointermove', show)
    target.addEventListener('pointerleave', hide)
  }

  tooltipRow(color, label, value) {
    return `
      <div class="flex items-center gap-2 py-0.5">
        <span class="w-2 h-2 rounded-full" style="background: ${color}"></span>
        <span class="text-gray-400">${label}</span>
        <span class="ml-auto pl-4 font-semibold text-gray-100">${value}</span>
      </div>`
  }

  // Round the top of the y-axis up to 3 even steps (17 -> 0/6/12/18)
  niceScale(maxVal) {
    const raw = maxVal / 3
    const magnitude = Math.pow(10, Math.floor(Math.log10(raw)))
    const step = [1, 2, 3, 4, 5, 6, 8, 10].map(m => m * magnitude).find(s => s >= raw)
    return { max: step * 3, ticks: [0, step, step * 2, step * 3] }
  }

  // Push end-of-line labels apart so close values (e.g. 17 / 16) don't overlap
  spreadLabels(items, gap, minY, maxY) {
    const sorted = [...items].sort((a, b) => a.y - b.y).map(item => ({ ...item, labelY: item.y }))
    for (let i = 1; i < sorted.length; i++) {
      sorted[i].labelY = Math.max(sorted[i].labelY, sorted[i - 1].labelY + gap)
    }
    const overflow = sorted[sorted.length - 1].labelY - maxY
    if (overflow > 0) sorted.forEach(item => { item.labelY -= overflow })
    for (let i = sorted.length - 2; i >= 0; i--) {
      sorted[i].labelY = Math.min(sorted[i].labelY, sorted[i + 1].labelY - gap)
    }
    sorted.forEach(item => { item.labelY = Math.max(item.labelY, minY) })
    return sorted
  }

  badgeWidth(value) {
    return 14 + String(value).length * 7
  }

  renderMini(data) {
    const width = 120
    const height = 32
    const maxVal = Math.max(...data.map(d => d.scope), 1)

    const xScale = (i) => (i / (data.length - 1 || 1)) * width
    const yScale = (v) => height - (v / maxVal) * height

    const completedArea = this.areaPath(data.map((d, i) => [xScale(i), yScale(d.completed)]), height)
    const scopeLine = this.linePath(data.map((d, i) => [xScale(i), yScale(d.scope)]))

    this.element.innerHTML = `
      <svg viewBox="0 0 ${width} ${height}" class="w-full h-8">
        <path d="${completedArea}" fill="#92E8D4" opacity="0.4" />
        <path d="${scopeLine}" fill="none" stroke="#6b7280" stroke-width="1" />
      </svg>
    `
  }

  linePath(points) {
    if (points.length === 0) return ""
    return points.map((p, i) => `${i === 0 ? 'M' : 'L'}${p[0]},${p[1]}`).join(' ')
  }

  // Monotone cubic (Fritsch–Carlson) so curves never overshoot the data, e.g. dip below 0
  smoothPath(points) {
    if (points.length < 3) return this.linePath(points)

    const n = points.length
    const slopes = []
    for (let i = 0; i < n - 1; i++) {
      slopes.push((points[i + 1][1] - points[i][1]) / (points[i + 1][0] - points[i][0]))
    }
    const tangents = [slopes[0]]
    for (let i = 1; i < n - 1; i++) {
      tangents.push(slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2)
    }
    tangents.push(slopes[n - 2])
    for (let i = 0; i < n - 1; i++) {
      if (slopes[i] === 0) {
        tangents[i] = 0
        tangents[i + 1] = 0
        continue
      }
      const a = tangents[i] / slopes[i]
      const b = tangents[i + 1] / slopes[i]
      const h = Math.hypot(a, b)
      if (h > 3) {
        tangents[i] = (3 / h) * a * slopes[i]
        tangents[i + 1] = (3 / h) * b * slopes[i]
      }
    }

    let d = `M${points[0][0]},${points[0][1]}`
    for (let i = 0; i < n - 1; i++) {
      const [x0, y0] = points[i]
      const [x1, y1] = points[i + 1]
      const dx = (x1 - x0) / 3
      d += ` C${x0 + dx},${y0 + tangents[i] * dx} ${x1 - dx},${y1 - tangents[i + 1] * dx} ${x1},${y1}`
    }
    return d
  }

  areaPath(points, baseline) {
    if (points.length === 0) return ""
    const line = this.smoothPath(points)
    return `${line} L${points[points.length - 1][0]},${baseline} L${points[0][0]},${baseline} Z`
  }

  daysBetween(dateA, dateB) {
    const a = new Date(dateA)
    const b = new Date(dateB)
    return (b - a) / (1000 * 60 * 60 * 24)
  }

  formatDate(dateStr) {
    const d = new Date(dateStr + 'T00:00:00')
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
  }
}
