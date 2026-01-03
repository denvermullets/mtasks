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

  # Reorganizes grouped issues for swimlane rendering
  # Converts column-first structure to row-first structure
  def organize_for_swimlanes(grouped_issues)
    # Check if we have subgroups in any column
    has_subgroups = grouped_issues.values.any? { |group_data| group_data[:subgroups].present? }
    return nil unless has_subgroups

    # Collect all unique subgroup names across all columns
    all_subgroup_names = grouped_issues.values.flat_map do |group_data|
      group_data[:subgroups]&.keys || []
    end.uniq

    # Build swimlane structure: { row_name => { column_name => data } }
    swimlanes = {}
    all_subgroup_names.each do |subgroup_name|
      swimlanes[subgroup_name] = {}
      grouped_issues.each do |column_name, column_data|
        subgroup_data = column_data[:subgroups]&.[](subgroup_name)
        swimlanes[subgroup_name][column_name] = {
          object: column_data[:object],
          issues: subgroup_data&.[](:issues) || []
        }
      end
    end

    swimlanes
  end
end
