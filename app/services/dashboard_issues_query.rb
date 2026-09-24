# Resolves a dashboard's groups into filtered, sorted issue lists plus dashboard-wide
# "due today" / "overdue" counts. Team access is enforced at read time: sources pointing
# at teams the user isn't a member of (or archived teams) are dropped here, not via callbacks.
class DashboardIssuesQuery < Service
  FILTERS = %w[today week hot open].freeze
  DEFAULT_FILTER = 'today'.freeze

  # `search` narrows the rows only; `team_id` (already validated against the user's teams)
  # narrows rows and counts; `team_ids` are the accessible teams behind this dashboard's
  # sources, for the header's team picker. Each `groups` entry is { group:, issues:, inaccessible: },
  # where `inaccessible` means the group has sources but none resolve to a team or project
  # the user can still see.
  Result = Data.define(:groups, :due_today_count, :overdue_count, :filter, :today, :search, :team_id, :team_ids)
  # `team_ids` / `project_ids` are every source; `all_*` are the subset that shows every issue.
  # The rest only contribute issues assigned to the user.
  Sources = Data.define(:team_ids, :project_ids, :all_team_ids, :all_project_ids) do
    def empty?
      team_ids.empty? && project_ids.empty?
    end
  end

  # Every option past `dashboard:` mirrors one URL param; they're keywords with defaults, so
  # the count is fine here.
  def initialize(user:, dashboard:, filter: DEFAULT_FILTER, mine: false, today: nil, search: nil, team_id: nil) # rubocop:disable Metrics/ParameterLists
    @user = user
    @dashboard = dashboard
    @filter = FILTERS.include?(filter.to_s) ? filter.to_s : DEFAULT_FILTER
    @mine = ActiveModel::Type::Boolean.new.cast(mine)
    @today = today || Time.current.in_time_zone(user.time_zone).to_date
    @search = search.to_s.strip
    @requested_team_id = team_id
  end

  def call
    groups = @dashboard.groups.includes(:sources).to_a
    resolved = groups.map { |group| [group, resolve_sources(group)] }
    union = union_sources(resolved.map(&:last))

    Result.new(
      groups: resolved.map { |group, sources| group_entry(group, sources) },
      due_today_count: count_for(union, @today),
      overdue_count: count_for(union, ...@today),
      filter: @filter,
      today: @today,
      search: @search,
      team_id: team_id,
      team_ids: (union.team_ids + union.project_ids.map { |id| accessible_project_ids[id] }).uniq
    )
  end

  private

  def accessible_team_ids
    @accessible_team_ids ||= @user.teams.not_archived.pluck(:id)
  end

  # A team the user isn't in (or a blank / non-numeric value) means "no team filter", so a
  # forged id can't reveal anything.
  def team_id
    return @team_id if defined?(@team_id)

    id = @requested_team_id.to_i
    @team_id = accessible_team_ids.include?(id) ? id : nil
  end

  # One query for the whole dashboard: every Project source, limited to accessible teams.
  # Returns { project_id => team_id } so the owning team is known without another query.
  def accessible_project_ids
    @accessible_project_ids ||= begin
      requested = @dashboard.groups.flat_map { |group| source_ids(group, 'Project') }.uniq
      if requested.empty?
        {}
      else
        Project.where(id: requested, team_id: accessible_team_ids).pluck(:id, :team_id).to_h
      end
    end
  end

  def source_ids(group, type)
    group.source_ids_for(type)
  end

  def resolve_sources(group)
    team_ids = source_ids(group, 'Team') & accessible_team_ids
    project_ids = source_ids(group, 'Project').select { |id| accessible_project_ids.include?(id) }

    Sources.new(
      team_ids: team_ids,
      project_ids: project_ids,
      all_team_ids: group.source_ids_for('Team', include_all: true) & team_ids,
      all_project_ids: group.source_ids_for('Project', include_all: true) & project_ids
    )
  end

  def group_entry(group, sources)
    { group: group, issues: issues_for(sources), inaccessible: group.sources.any? && sources.empty? }
  end

  def union_sources(all_sources)
    Sources.new(**Sources.members.index_with { |key| all_sources.flat_map(&key).uniq })
  end

  def base_scope(sources)
    return Issue.none if sources.empty?

    scope = Issue.unresolved.where(team_id: accessible_team_ids)
    scope = source_scope(scope, sources)
    scope = scope.where(assignee_id: @user.id) if @mine
    scope = scope.where(team_id: team_id) if team_id
    scope
  end

  # Every issue from an include_all source, plus the user's own issues from the rest.
  def source_scope(scope, sources)
    assigned = scope.where(assignee_id: @user.id)

    scope.where(team_id: sources.all_team_ids)
         .or(scope.where(project_id: sources.all_project_ids))
         .or(assigned.where(team_id: sources.team_ids))
         .or(assigned.where(project_id: sources.project_ids))
  end

  # Search applies to the rows only; the header counts (count_for) ignore it on purpose.
  def issues_for(sources)
    return [] if sources.empty?

    apply_filter(base_scope(sources).matching_search(@search))
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
