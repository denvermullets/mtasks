# rubocop:disable Metrics/ClassLength
class IssueDisplayService
  attr_reader :issues, :options

  def initialize(issues, options = {})
    @issues = issues
    @options = default_options.merge(options)
  end

  def grouped_issues
    filtered = filter_issues
    sorted = sort_issues(filtered)
    group_issues(sorted)
  end

  def filter_issues
    result = issues
    result = filter_by_completion(result) if options[:completed_filter].present?
    result = filter_sub_issues(result) unless options[:show_sub_issues]
    result
  end

  def sort_issues(issue_scope)
    case options[:order_by]
    when 'priority'
      issue_scope.order(priority: :asc)
    when 'due_date'
      issue_scope.order(Arel.sql('due_date IS NULL, due_date ASC'))
    when 'created_at'
      issue_scope.order(created_at: :desc)
    when 'updated_at'
      issue_scope.order(updated_at: :desc)
    else
      issue_scope
    end
  end

  def group_issues(issue_scope)
    primary_groups = case options[:group_by]
                     when 'priority'
                       group_by_priority(issue_scope)
                     when 'status'
                       group_by_status(issue_scope)
                     when 'none'
                       { 'All Issues' => { object: nil, issues: issue_scope } }
                     when 'lane', 'label', 'parent_issue', 'project', 'milestone', 'assignee'
                       group_by_association(issue_scope, options[:group_by].to_sym)
                     end

    # Apply sub-grouping if specified and not 'none'
    if options[:sub_group_by].present? && options[:sub_group_by] != 'none'
      apply_sub_grouping(primary_groups)
    else
      primary_groups
    end
  end

  private

  def default_options
    {
      view_mode: 'board',
      group_by: 'lane',
      sub_group_by: 'none',
      order_by: 'manual',
      show_sub_issues: true,
      show_empty_groups: false,
      completed_filter: nil,
      visible_properties: UserPreference::AVAILABLE_PROPERTIES
    }
  end

  def filter_by_completion(issue_scope)
    cutoff = case options[:completed_filter]
             when 'past_day' then 1.day.ago
             when 'past_week' then 1.week.ago
             when 'past_month' then 1.month.ago
             when 'all_time', 'all_completed' then return issue_scope
             end

    if cutoff
      issue_scope.where('completed_at IS NULL OR completed_at >= ?', cutoff)
    else
      issue_scope.not_completed
    end
  end

  def filter_sub_issues(issue_scope)
    issue_scope.where(parent_issue_id: nil)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def group_by_association(issue_scope, association_name)
    groups = {}
    team = issue_scope.first&.team
    return groups unless team

    all_groups = case association_name
                 when :lane
                   team.lanes.order(:position)
                 when :project
                   team.projects
                 when :milestone
                   team.milestones
                 when :assignee
                   team.users
                 when :label
                   team.labels
                 when :parent_issue
                   # For parent_issue grouping, we'll handle it differently
                   nil
                 end

    all_groups&.each do |group|
      issues_in_group = if association_name == :label
                          # Labels use has_many :through, so we need to join through issue_labels
                          issue_scope.joins(:labels).where(labels: { id: group.id }).distinct
                        else
                          issue_scope.where(association_name => group)
                        end
      next if issues_in_group.empty? && !options[:show_empty_groups]

      groups[group_name_for(group)] = { object: group, issues: issues_in_group }
    end

    ungrouped = if association_name == :label
                  # Issues with no labels
                  issue_scope.left_joins(:labels).where(labels: { id: nil })
                else
                  issue_scope.where(association_name => nil)
                end
    if ungrouped.any? || options[:show_empty_groups]
      groups["No #{association_name.to_s.titleize}"] = { object: nil, issues: ungrouped }
    end

    groups
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  def group_by_priority(issue_scope)
    groups = {}

    Issue.priorities.each_key do |priority_key|
      issues_in_group = issue_scope.where(priority: priority_key)
      next if issues_in_group.empty? && !options[:show_empty_groups]

      label = priority_key.to_s.titleize
      label = 'No Priority' if priority_key == 'no_priority'
      groups[label] = { object: priority_key, issues: issues_in_group }
    end

    groups
  end

  def group_by_status(issue_scope)
    # Status is represented by lanes, so group by lane for correct custom lane support
    group_by_association(issue_scope, :lane)
  end

  def group_name_for(object)
    return object.name if object.respond_to?(:name)

    object.to_s
  end

  def apply_sub_grouping(primary_groups)
    primary_groups.transform_values do |primary_group_data|
      issues_in_primary_group = primary_group_data[:issues]

      # Apply secondary grouping to issues within this primary group
      subgroups = case options[:sub_group_by]
                  when 'priority'
                    group_by_priority(issues_in_primary_group)
                  when 'status'
                    group_by_status(issues_in_primary_group)
                  when 'lane', 'label', 'parent_issue', 'project', 'milestone', 'assignee'
                    group_by_association(issues_in_primary_group, options[:sub_group_by].to_sym)
                  else
                    { 'All' => { object: nil, issues: issues_in_primary_group } }
                  end

      # Return the primary group with nested subgroups
      primary_group_data.merge(subgroups: subgroups)
    end
  end
end
# rubocop:enable Metrics/ClassLength
