module IssuesHelper
  def render_priority_icon(priority)
    case priority
    when 'urgent'
      content_tag(:div, '⚠️', class: 'text-red-500')
    when 'high'
      content_tag(:div, '🔴', class: 'text-orange-500')
    when 'medium'
      content_tag(:div, '🟡', class: 'text-yellow-500')
    when 'low'
      content_tag(:div, '🔵', class: 'text-blue-500')
    else
      content_tag(:div, '⚪', class: 'text-gray-500')
    end
  end

  def render_lane_icon(lane)
    case lane&.name&.downcase
    when 'backlog'
      content_tag(:div, '◯', class: 'text-gray-500')
    when 'in progress'
      content_tag(:div, '◐', class: 'text-blue-500')
    when 'done'
      content_tag(:div, '✓', class: 'text-green-500')
    when 'cancelled'
      content_tag(:div, '✕', class: 'text-gray-600')
    else
      content_tag(:div, '•', class: 'text-gray-500')
    end
  end
end
