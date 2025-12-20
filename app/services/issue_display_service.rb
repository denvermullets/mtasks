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
    case options[:group_by]
    when 'lane'
      group_by_association(issue_scope, :lane)
    when 'priority'
      group_by_priority(issue_scope)
    when 'status'
      group_by_status(issue_scope)
    when 'project'
      group_by_association(issue_scope, :project)
    when 'milestone'
      group_by_association(issue_scope, :milestone)
    when 'assignee'
      group_by_association(issue_scope, :assignee)
    when 'none'
      { 'All Issues' => { object: nil, issues: issue_scope } }
    else
      group_by_association(issue_scope, :lane)
    end
  end

  private

  def default_options
    {
      view_mode: 'board',
      group_by: 'lane',
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
             when 'all_time' then return issue_scope
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
                 end

    all_groups&.each do |group|
      issues_in_group = issue_scope.where(association_name => group)
      next if issues_in_group.empty? && !options[:show_empty_groups]

      groups[group_name_for(group)] = { object: group, issues: issues_in_group }
    end

    ungrouped = issue_scope.where(association_name => nil)
    if ungrouped.any? || options[:show_empty_groups]
      groups["No #{association_name.to_s.titleize}"] = { object: nil, issues: ungrouped }
    end

    groups
  end

  def group_by_priority(issue_scope)
    groups = {}

    Issue.priorities.keys.each do |priority_key|
      issues_in_group = issue_scope.where(priority: priority_key)
      next if issues_in_group.empty? && !options[:show_empty_groups]

      label = priority_key.to_s.titleize
      label = 'No Priority' if priority_key == 'no_priority'
      groups[label] = { object: priority_key, issues: issues_in_group }
    end

    groups
  end

  def group_by_status(issue_scope)
    statuses = {
      'Backlog' => issue_scope.where(started_at: nil, completed_at: nil, canceled_at: nil),
      'In Progress' => issue_scope.in_progress,
      'Completed' => issue_scope.completed,
      'Canceled' => issue_scope.where.not(canceled_at: nil)
    }

    statuses.each_with_object({}) do |(status_name, issues_in_status), result|
      next if issues_in_status.empty? && !options[:show_empty_groups]

      result[status_name] = { object: status_name.downcase.tr(' ', '_'), issues: issues_in_status }
    end
  end

  def group_name_for(object)
    return object.name if object.respond_to?(:name)

    object.to_s
  end
end
