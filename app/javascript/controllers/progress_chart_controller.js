import { Controller } from "@hotwired/stimulus"

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
    const width = 600
    const height = 200
    const padding = { top: 10, right: 10, bottom: 30, left: 35 }
    const chartW = width - padding.left - padding.right
    const chartH = height - padding.top - padding.bottom

    const maxVal = Math.max(
      ...data.map(d => d.scope),
      ...(this.expectedValue || []).map(d => d.value),
      1
    )

    const xScale = (i) => padding.left + (i / (data.length - 1 || 1)) * chartW
    const yScale = (v) => padding.top + chartH - (v / maxVal) * chartH

    // Build area paths
    const scopeArea = this.areaPath(data.map((d, i) => [xScale(i), yScale(d.scope)]), yScale(0))
    const scopeLine = this.linePath(data.map((d, i) => [xScale(i), yScale(d.scope)]))
    const startedArea = this.areaPath(data.map((d, i) => [xScale(i), yScale(d.started)]), yScale(0))
    const completedArea = this.areaPath(data.map((d, i) => [xScale(i), yScale(d.completed)]), yScale(0))
    const completedLine = this.linePath(data.map((d, i) => [xScale(i), yScale(d.completed)]))

    // Expected progress line
    let expectedLine = ""
    if (this.expectedValue && this.expectedValue.length === 2) {
      const startDate = data[0].date
      const endDate = data[data.length - 1].date
      const expStart = this.expectedValue[0]
      const expEnd = this.expectedValue[1]

      // Map expected dates to x positions
      const totalDays = this.daysBetween(startDate, endDate)
      const expStartX = padding.left + (this.daysBetween(startDate, expStart.date) / (totalDays || 1)) * chartW
      const expEndX = padding.left + (this.daysBetween(startDate, expEnd.date) / (totalDays || 1)) * chartW

      expectedLine = `<line x1="${expStartX}" y1="${yScale(expStart.value)}" x2="${expEndX}" y2="${yScale(expEnd.value)}"
        stroke="#ef4444" stroke-width="1.5" stroke-dasharray="6,4" opacity="0.7" />`
    }

    // Date labels
    const firstDate = this.formatDate(data[0].date)
    const lastDate = this.formatDate(data[data.length - 1].date)

    // Y-axis labels
    const yLabels = [0, Math.round(maxVal / 2), maxVal]

    const lastScope = data[data.length - 1].scope
    const lastStarted = data[data.length - 1].started
    const lastCompleted = data[data.length - 1].completed

    this.element.innerHTML = `
      <div class="mb-3 flex items-center gap-6 text-xs">
        <div class="flex items-center gap-1.5">
          <span class="w-2.5 h-2.5 rounded-sm" style="background: #6b7280"></span>
          <span class="text-gray-400">Scope</span>
          <span class="text-gray-300 font-medium ml-1">${lastScope}</span>
        </div>
        <div class="flex items-center gap-1.5">
          <span class="w-2.5 h-2.5 rounded-sm" style="background: #eab308"></span>
          <span class="text-gray-400">Started</span>
          <span class="text-gray-300 font-medium ml-1">${lastStarted}</span>
        </div>
        <div class="flex items-center gap-1.5">
          <span class="w-2.5 h-2.5 rounded-sm" style="background: #6366f1"></span>
          <span class="text-gray-400">Completed</span>
          <span class="text-gray-300 font-medium ml-1">${lastCompleted}</span>
        </div>
        ${this.behindScheduleValue ? '<span class="text-red-400 ml-auto text-xs">Behind schedule</span>' : ''}
      </div>
      <svg viewBox="0 0 ${width} ${height}" class="w-full" style="max-height: ${height}px">
        <!-- Y-axis grid lines -->
        ${yLabels.map(v => `
          <line x1="${padding.left}" y1="${yScale(v)}" x2="${width - padding.right}" y2="${yScale(v)}"
            stroke="#374151" stroke-width="0.5" />
          <text x="${padding.left - 8}" y="${yScale(v) + 4}" text-anchor="end"
            fill="#6b7280" font-size="10">${v}</text>
        `).join('')}

        <!-- Scope area -->
        <path d="${scopeArea}" fill="#6b7280" opacity="0.15" />
        <path d="${scopeLine}" fill="none" stroke="#6b7280" stroke-width="1.5" />

        <!-- Started area -->
        <path d="${startedArea}" fill="#eab308" opacity="0.1" />

        <!-- Completed area -->
        <path d="${completedArea}" fill="#6366f1" opacity="0.3" />
        <path d="${completedLine}" fill="none" stroke="#6366f1" stroke-width="2" />

        <!-- Expected line -->
        ${expectedLine}

        <!-- Date labels -->
        <text x="${padding.left}" y="${height - 5}" fill="#6b7280" font-size="11">${firstDate}</text>
        <text x="${width - padding.right}" y="${height - 5}" text-anchor="end" fill="#6b7280" font-size="11">${lastDate}</text>
      </svg>
    `
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
        <path d="${completedArea}" fill="#6366f1" opacity="0.4" />
        <path d="${scopeLine}" fill="none" stroke="#6b7280" stroke-width="1" />
      </svg>
    `
  }

  linePath(points) {
    if (points.length === 0) return ""
    return points.map((p, i) => `${i === 0 ? 'M' : 'L'}${p[0]},${p[1]}`).join(' ')
  }

  areaPath(points, baseline) {
    if (points.length === 0) return ""
    const line = this.linePath(points)
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
