module IssuesHelper
  # Reorganizes grouped issues for swimlane rendering
  # Converts column-first structure to row-first structure
  def organize_for_swimlanes(grouped_issues)
    return nil unless subgroups?(grouped_issues)

    subgroup_names = collect_subgroup_names(grouped_issues)
    build_swimlanes(subgroup_names, grouped_issues)
  end

  PRIORITY_TAG_STYLES = {
    'urgent' => { bg: 'rgba(226, 75, 74, 0.15)', fg: '#e77676', label: 'URG' },
    'high' => { bg: 'rgba(226, 75, 74, 0.15)', fg: '#e77676', label: 'HIGH' },
    'medium' => { bg: 'rgba(239, 159, 39, 0.15)', fg: '#efb060', label: 'MED' },
    'low' => { bg: 'rgba(128, 128, 128, 0.15)', fg: '#9ca3af', label: 'LOW' }
  }.freeze

  def mobile_priority_tag(issue)
    style = PRIORITY_TAG_STYLES[issue.priority]
    return nil unless style

    content_tag(:span,
                style[:label],
                class: 'text-[10px] px-1.5 py-0.5 rounded font-medium flex-shrink-0 tracking-wide',
                style: "background: #{style[:bg]}; color: #{style[:fg]};")
  end

  # Picks the single most-relevant property to show in the mobile list row's right slot.
  # Precedence: priority > assignee > labels > comments > nothing.
  # Returns :priority, :assignee, :labels, :comments, or nil.
  def mobile_row_right_slot(issue, visible_properties)
    mobile_slot_candidates(issue, visible_properties).find { |slot| mobile_slot_present?(slot, issue) }
  end

  def mobile_slot_candidates(_issue, visible_properties)
    %i[priority assignee labels comments].select do |slot|
      slot == :comments || visible_properties.include?(slot.to_s)
    end
  end

  def mobile_slot_present?(slot, issue)
    case slot
    when :priority then !issue.no_priority?
    when :assignee then issue.assignee.present?
    when :labels then issue.labels.any?
    when :comments then issue.comments.size.positive?
    end
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

    return names unless names.intersect?(priority_display_names)

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
