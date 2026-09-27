# Resolves a dashboard's groups into filtered, sorted issue lists plus dashboard-wide
# "due today" / "overdue" counts. Team access is enforced at read time: sources pointing
# at teams the user isn't a member of (or archived teams) are dropped here, not via callbacks.
class DashboardIssuesQuery < Service
  FILTERS = %w[today week hot open].freeze
  DEFAULT_FILTER = 'today'.freeze
  # An issue without its own due date inherits its project's, so a dated project's work shows
  # up in the date tabs without dating every issue. Needs `projects` joined (see base_scope).
  DUE_DATE_SQL = 'COALESCE(issues.due_date, projects.due_date)'.freeze

  # `search` narrows the rows only; `team_id` (already validated against the user's teams)
  # narrows rows and counts; `team_ids` are the accessible teams behind this dashboard's
  # sources, for the header's team picker. Each `groups` entry is { group:, issues:, inaccessible: },
  # where `inaccessible` means the group has sources but nothing the user can still see is left
  # to match.
  Result = Data.define(:groups, :due_today_count, :overdue_count, :filter, :today, :search, :team_id, :team_ids)
  # Teams and projects define the group's pool: `team_ids` / `project_ids` are every such source,
  # `all_*` the subset that shows every issue (the rest only contribute issues assigned to the user).
  # Labels narrow that pool to issues carrying any of `label_ids`; a labels-only group pools every
  # issue on the labels' teams. `pooled` / `labeled` say whether the group had team/project or label
  # sources at all, so a source the user lost access to empties the group instead of widening it.
  Sources = Data.define(:team_ids, :project_ids, :all_team_ids, :all_project_ids, :label_ids, :pooled, :labeled) do
    def empty?
      return true unless pooled || labeled

      (pooled && team_ids.empty? && project_ids.empty?) || (labeled && label_ids.empty?)
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
    all_sources = resolved.map(&:last).reject(&:empty?)

    Result.new(
      groups: resolved.map { |group, sources| group_entry(group, sources) },
      due_today_count: count_for(all_sources, '=', @today),
      overdue_count: count_for(all_sources, '<', @today),
      filter: @filter,
      today: @today,
      search: @search,
      team_id: team_id,
      team_ids: all_sources.flat_map { |sources| source_team_ids(sources) }.uniq
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

  # Same as accessible_project_ids, for Label sources. Labels are team-scoped.
  def accessible_label_ids
    @accessible_label_ids ||= begin
      requested = @dashboard.groups.flat_map { |group| source_ids(group, 'Label') }.uniq
      if requested.empty?
        {}
      else
        Label.where(id: requested, team_id: accessible_team_ids).pluck(:id, :team_id).to_h
      end
    end
  end

  # Accessible teams a group's issues can come from: its pool, or the labels' teams when it has none.
  def source_team_ids(sources)
    return label_team_ids(sources) unless sources.pooled

    (sources.team_ids + sources.project_ids.map { |id| accessible_project_ids[id] }).uniq
  end

  def label_team_ids(sources)
    sources.label_ids.map { |id| accessible_label_ids[id] }.uniq
  end

  def source_ids(group, type)
    group.source_ids_for(type)
  end

  def resolve_sources(group)
    team_ids = source_ids(group, 'Team') & accessible_team_ids
    project_ids = source_ids(group, 'Project').select { |id| accessible_project_ids.include?(id) }
    requested_labels = source_ids(group, 'Label')

    Sources.new(
      team_ids: team_ids,
      project_ids: project_ids,
      all_team_ids: group.source_ids_for('Team', include_all: true) & team_ids,
      all_project_ids: group.source_ids_for('Project', include_all: true) & project_ids,
      label_ids: requested_labels.select { |id| accessible_label_ids.include?(id) },
      pooled: group.sources.any? { |source| source.source_type != 'Label' },
      labeled: requested_labels.any?
    )
  end

  def group_entry(group, sources)
    { group: group, issues: issues_for(sources), inaccessible: group.sources.any? && sources.empty? }
  end

  def base_scope(sources)
    return Issue.none if sources.empty?

    scope = Issue.unresolved.left_joins(:project).where(team_id: accessible_team_ids)
    scope = source_scope(scope, sources)
    scope = scope.where(assignee_id: @user.id) if @mine
    scope = scope.where(team_id: team_id) if team_id
    scope
  end

  def source_scope(scope, sources)
    scope = sources.pooled ? pool_scope(scope, sources) : scope.where(team_id: label_team_ids(sources))
    return scope unless sources.labeled

    # Subquery (not an issue_labels join) so an issue carrying several of the labels stays one row.
    scope.where(id: IssueLabel.where(label_id: sources.label_ids).select(:issue_id))
  end

  # Every issue from an include_all source, plus the user's own issues from the rest.
  def pool_scope(scope, sources)
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
      .order(Arel.sql("#{DUE_DATE_SQL} ASC NULLS LAST"), :priority, :id)
      .to_a
  end

  def apply_filter(scope)
    case @filter
    when 'today' then scope.where("#{DUE_DATE_SQL} <= ?", @today)
    when 'week' then scope.where("#{DUE_DATE_SQL} <= ?", @today + 6)
    when 'hot' then scope.hot
    else scope
    end
  end

  # Header counts ignore the active filter tab; they always mean "due today" and "overdue".
  # An issue counts once even when several groups show it. `operator` is one of the literals
  # passed from #call, never user input.
  def count_for(all_sources, operator, date)
    return 0 if all_sources.empty?

    in_any_group = all_sources.map { |sources| Issue.where(id: base_scope(sources).select(:id)) }.reduce(:or)
    in_any_group.left_joins(:project).where("#{DUE_DATE_SQL} #{operator} ?", date).count
  end
end
