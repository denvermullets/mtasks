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

  def render_group_icon(group_object)
    case group_object
    when Lane
      render_lane_icon(group_object)
    when String
      # Assume it's a priority
      render_priority_icon(group_object)
    when Project
      content_tag(:div, '📁', class: 'text-gray-500')
    when Milestone
      content_tag(:div, '🎯', class: 'text-gray-500')
    when Label
      content_tag(:div, '🏷️', class: 'text-gray-500')
    when User
      content_tag(:div, '👤', class: 'text-gray-500')
    else
      content_tag(:div, class: 'w-4 h-4 rounded-full border border-gray-600') { '' }
    end
  end

  # Reorganizes grouped issues for swimlane rendering
  # Converts column-first structure to row-first structure
  def organize_for_swimlanes(grouped_issues)
    return nil unless subgroups?(grouped_issues)

    subgroup_names = collect_subgroup_names(grouped_issues)
    build_swimlanes(subgroup_names, grouped_issues)
  end

  private

  def subgroups?(grouped_issues)
    grouped_issues.values.any? { |group_data| group_data[:subgroups].present? }
  end

  def collect_subgroup_names(grouped_issues)
    names = grouped_issues.values.flat_map do |group_data|
      group_data[:subgroups]&.keys || []
    end.uniq

    ensure_priority_order_with_all_rows(names)
  end

  def ensure_priority_order_with_all_rows(names)
    priority_display_names = Issue.priorities.keys.map { |p| p == 'no_priority' ? 'No Priority' : p.titleize }

    # Check if any names are priority values - if so, return ALL priorities in correct order
    return names unless names.intersect?(priority_display_names)

    # Return all priority rows in correct order (ensures empty rows maintain position)
    priority_display_names
  end

  def build_swimlanes(subgroup_names, grouped_issues)
    subgroup_names.to_h do |subgroup_name|
      [subgroup_name, build_swimlane_columns(subgroup_name, grouped_issues)]
    end
  end

  def build_swimlane_columns(subgroup_name, grouped_issues)
    grouped_issues.each_with_object({}) do |(column_name, column_data), columns|
      subgroup_data = column_data[:subgroups]&.[](subgroup_name)
      columns[column_name] = {
        object: column_data[:object],
        issues: subgroup_data&.[](:issues) || []
      }
    end
  end
end
