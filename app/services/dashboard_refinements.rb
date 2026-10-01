# The dashboard header's sort and pickers (assignee, label, lane), normalized from URL
# params. Unknown values fall back to "no filter" / the default sort, so a forged param is harmless:
# every picker only narrows issues DashboardIssuesQuery already allows.
class DashboardRefinements
  SORTS = %w[due priority updated created].freeze
  DEFAULT_SORT = 'due'.freeze
  # `assignee=none` means unassigned issues.
  UNASSIGNED = 'none'.freeze

  # Needs `projects` joined for the due-date sorts (see DashboardIssuesQuery#base_scope).
  DUE_ORDER = Arel.sql("#{DashboardIssuesQuery::DUE_DATE_SQL} ASC NULLS LAST")

  attr_reader :sort, :assignee, :label, :status

  def initialize(sort: nil, assignee: nil, label: nil, status: nil)
    @sort = SORTS.include?(sort.to_s) ? sort.to_s : DEFAULT_SORT
    @assignee = normalize_assignee(assignee)
    @label = label.to_s.strip.presence
    @status = status.to_s.strip.presence
  end

  # Issues the dashboard starts from. With no status picked, completed/canceled issues stay hidden;
  # picking a lane (even a closed one like Done) shows whatever sits in it.
  def base_scope
    @status ? Issue.not_archived : Issue.unresolved
  end

  # Labels and lanes match by name, so "bug" / "In Progress" cover every team's label / lane of that
  # name; `team_ids` keeps that to teams the user can see.
  def narrow(scope, team_ids)
    scope = scope.where(assignee_id: @assignee == UNASSIGNED ? nil : @assignee.to_i) if @assignee
    scope = scope.where(lane_id: Lane.unscoped.where(team_id: team_ids, name: @status).select(:id)) if @status
    return scope unless @label

    labeled = IssueLabel.joins(:label).where(labels: { name: @label, team_id: team_ids })
    scope.where(id: labeled.select(:issue_id))
  end

  # Priority sorts ascending because the enum runs urgent (0) to no_priority (4).
  def order
    case @sort
    when 'priority' then [:priority, DUE_ORDER, :id]
    when 'updated' then [{ updated_at: :desc }, :id]
    when 'created' then [{ created_at: :desc }, :id]
    else [DUE_ORDER, :priority, :id]
    end
  end

  private

  # A user id (as a string, the way it arrives in the URL) or UNASSIGNED; anything else is no filter.
  def normalize_assignee(value)
    value = value.to_s
    return UNASSIGNED if value == UNASSIGNED

    value.to_i.positive? ? value.to_i.to_s : nil
  end
end
