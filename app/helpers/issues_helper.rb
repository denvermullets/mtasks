module IssuesHelper
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
