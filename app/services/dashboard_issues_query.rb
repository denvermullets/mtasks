# Resolves a dashboard's groups into filtered, sorted issue lists plus dashboard-wide
# "due today" / "overdue" counts. Team access is enforced at read time: sources pointing
# at teams the user isn't a member of (or archived teams) are dropped here, not via callbacks.
class DashboardIssuesQuery < Service
  FILTERS = %w[today week hot open].freeze
  DEFAULT_FILTER = 'today'.freeze

  Result = Data.define(:groups, :due_today_count, :overdue_count, :filter, :today)
  Sources = Data.define(:team_ids, :project_ids) do
    def empty?
      team_ids.empty? && project_ids.empty?
    end
  end

  def initialize(user:, dashboard:, filter: DEFAULT_FILTER, mine: false, today: nil)
    @user = user
    @dashboard = dashboard
    @filter = FILTERS.include?(filter.to_s) ? filter.to_s : DEFAULT_FILTER
    @mine = ActiveModel::Type::Boolean.new.cast(mine)
    @today = today || Time.current.in_time_zone(user.time_zone).to_date
  end

  def call
    groups = @dashboard.groups.includes(:sources).to_a
    resolved = groups.map { |group| [group, resolve_sources(group)] }
    union = union_sources(resolved.map(&:last))

    Result.new(
      groups: resolved.map { |group, sources| { group: group, issues: issues_for(sources) } },
      due_today_count: count_for(union, @today),
      overdue_count: count_for(union, ...@today),
      filter: @filter,
      today: @today
    )
  end

  private

  def accessible_team_ids
    @accessible_team_ids ||= @user.teams.not_archived.pluck(:id)
  end

  # One query for the whole dashboard: every Project source, limited to accessible teams.
  def accessible_project_ids
    @accessible_project_ids ||= begin
      requested = @dashboard.groups.flat_map { |group| source_ids(group, 'Project') }.uniq
      if requested.empty?
        Set.new
      else
        Project.where(id: requested, team_id: accessible_team_ids).pluck(:id).to_set
      end
    end
  end

  def source_ids(group, type)
    group.sources.select { |source| source.source_type == type }.map(&:source_id)
  end

  def resolve_sources(group)
    Sources.new(
      team_ids: source_ids(group, 'Team') & accessible_team_ids,
      project_ids: source_ids(group, 'Project').select { |id| accessible_project_ids.include?(id) }
    )
  end

  def union_sources(all_sources)
    Sources.new(
      team_ids: all_sources.flat_map(&:team_ids).uniq,
      project_ids: all_sources.flat_map(&:project_ids).uniq
    )
  end

  def base_scope(sources)
    return Issue.none if sources.empty?

    scope = Issue.unresolved.where(team_id: accessible_team_ids)
    scope = scope.where(team_id: sources.team_ids).or(scope.where(project_id: sources.project_ids))
    scope = scope.where(assignee_id: @user.id) if @mine
    scope
  end

  def issues_for(sources)
    return [] if sources.empty?

    apply_filter(base_scope(sources))
      .includes(:team, :project, :assignee, :lane)
      .order(Arel.sql('issues.due_date ASC NULLS LAST'), :priority, :id)
      .to_a
  end

  def apply_filter(scope)
    case @filter
    when 'today' then scope.due_on_or_before(@today)
    when 'week' then scope.due_on_or_before(@today + 6)
    when 'hot' then scope.hot
    else scope
    end
  end

  # Header counts ignore the active filter tab; they always mean "due today" and "overdue".
  def count_for(sources, due_date)
    return 0 if sources.empty?

    base_scope(sources).where(due_date: due_date).count
  end
end
