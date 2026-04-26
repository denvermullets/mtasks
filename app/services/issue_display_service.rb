# rubocop:disable Metrics/ClassLength
class IssueDisplayService
  attr_reader :issues, :options, :team

  def initialize(issues, options = {}, team = nil)
    @issues = issues
    @options = default_options.merge(options)
    @team = team
  end

  def grouped_issues
    filtered = filter_issues
    sorted = sort_issues(filtered)
    group_issues(sorted)
  end

  def empty_groups
    return [] if options[:show_empty_groups]

    @empty_groups ||= []
  end

  ATTRIBUTE_FILTERS = {
    lane_ids: :filter_by_lane,
    assignee_ids: :filter_by_assignees,
    creator_ids: :filter_by_creators,
    priority: :filter_by_priority,
    label_ids: :filter_by_labels,
    project_ids: :filter_by_project
  }.freeze

  def filter_issues
    @empty_groups = [] # Reset empty groups tracking
    result = options[:search_query].present? ? filter_by_search_term(issues) : filter_by_completion(issues)
    result = filter_sub_issues(result) unless options[:show_sub_issues]
    ATTRIBUTE_FILTERS.each do |key, method|
      result = send(method, result) if options[key].present?
    end
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
    loaded_issues = issue_scope.to_a

    primary_groups = case options[:group_by]
                     when 'priority'
                       group_by_priority(loaded_issues)
                     when 'status'
                       group_by_status(loaded_issues)
                     when 'none'
                       { 'All Issues' => { object: nil, issues: loaded_issues } }
                     when 'lane', 'label', 'parent_issue', 'project', 'assignee'
                       group_by_association(loaded_issues, options[:group_by].to_sym)
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
      view_mode: 'list',
      group_by: 'lane',
      sub_group_by: 'none',
      order_by: 'manual',
      show_sub_issues: true,
      show_empty_groups: false,
      completed_filter: nil,
      search_query: nil,
      visible_properties: UserPreference::AVAILABLE_PROPERTIES
    }
  end

  def filter_by_search_term(issue_scope)
    term = options[:search_query].to_s.strip
    return issue_scope if term.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
    issue_scope.where('title ILIKE :q OR description ILIKE :q', q: pattern)
  end

  def filter_by_completion(issue_scope)
    return issue_scope if options[:completed_filter].in?(%w[all_time all_completed])

    cutoff = case options[:completed_filter]
             when 'past_day' then 1.day.ago
             when 'past_week' then 1.week.ago
             when 'past_month' then 1.month.ago
             end

    if cutoff
      issue_scope.where(
        '(issues.completed_at IS NULL AND issues.canceled_at IS NULL) ' \
        'OR issues.completed_at >= :cutoff OR issues.canceled_at >= :cutoff',
        cutoff: cutoff
      )
    else
      issue_scope.where(completed_at: nil, canceled_at: nil)
    end
  end

  def filter_sub_issues(issue_scope)
    issue_scope.where(parent_issue_id: nil)
  end

  def filter_by_lane(issue_scope)
    issue_scope.where(lane_id: options[:lane_ids])
  end

  def filter_by_assignees(issue_scope)
    issue_scope.where(assignee_id: options[:assignee_ids])
  end

  def filter_by_creators(issue_scope)
    issue_scope.where(creator_id: options[:creator_ids])
  end

  def filter_by_priority(issue_scope)
    issue_scope.where(priority: options[:priority])
  end

  def filter_by_labels(issue_scope)
    issue_scope.joins(:labels).where(labels: { id: options[:label_ids] }).distinct
  end

  def filter_by_project(issue_scope)
    issue_scope.where(project_id: options[:project_ids])
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def group_by_association(loaded_issues, association_name)
    groups = {}
    team = @team || loaded_issues.first&.team
    return groups unless team

    all_groups = case association_name
                 when :lane then team.lanes.order(:position)
                 when :project then team.projects
                 when :assignee then team.users
                 when :label then team.labels
                 when :parent_issue then nil
                 end

    if association_name == :label
      issues_by_label_id = Hash.new { |h, k| h[k] = [] }
      loaded_issues.each do |issue|
        issue.labels.each { |label| issues_by_label_id[label.id] << issue }
      end
    else
      fk = "#{association_name}_id"
      issues_by_fk = loaded_issues.group_by { |i| i.public_send(fk) }
    end

    all_groups&.each do |group|
      issues_in_group = if association_name == :label
                          issues_by_label_id[group.id]
                        else
                          issues_by_fk[group.id] || []
                        end

      if issues_in_group.empty? && !options[:show_empty_groups]
        @empty_groups << { name: group_name_for(group), object: group }
        next
      end

      groups[group_name_for(group)] = { object: group, issues: issues_in_group }
    end

    # Add "No X" group for optional associations (skip lane since it's required)
    unless association_name == :lane
      ungrouped = if association_name == :label
                    loaded_issues.select { |issue| issue.labels.empty? }
                  else
                    fk ||= "#{association_name}_id"
                    issues_by_fk[nil] || loaded_issues.select { |i| i.public_send(fk).nil? }
                  end
      if ungrouped.any? || options[:show_empty_groups]
        groups["No #{association_name.to_s.titleize}"] = { object: nil, issues: ungrouped }
      end
    end

    groups
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  def group_by_priority(loaded_issues)
    groups = {}
    by_priority = loaded_issues.group_by(&:priority)

    Issue.priorities.each_key do |priority_key|
      issues_in_group = by_priority[priority_key] || []
      label = priority_key.to_s.titleize
      label = 'No Priority' if priority_key == 'no_priority'

      if issues_in_group.empty? && !options[:show_empty_groups]
        @empty_groups << { name: label, object: priority_key }
        next
      end

      groups[label] = { object: priority_key, issues: issues_in_group }
    end

    groups
  end

  def group_by_status(loaded_issues)
    # Status is represented by lanes, so group by lane for correct custom lane support
    group_by_association(loaded_issues, :lane)
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
                  when 'lane', 'label', 'parent_issue', 'project', 'assignee'
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
