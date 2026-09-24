module DashboardsHelper
  FILTER_TABS = [
    ['today', 'Due today'],
    ['week', 'This week'],
    ['hot', 'Urgent / High'],
    ['open', 'All open']
  ].freeze

  # Tailwind background class for the row's priority dot; colors match IconHelper#render_priority_icon.
  # Lives here rather than IssuesHelper only because that module is at its length limit.
  PRIORITY_DOT_CLASSES = {
    'urgent' => 'bg-red-400',
    'high' => 'bg-orange-400',
    'medium' => 'bg-yellow-400',
    'low' => 'bg-blue-400'
  }.freeze

  EMPTY_GROUP_MESSAGES = {
    'today' => 'Nothing due today',
    'week' => 'Nothing due this week',
    'hot' => 'Nothing urgent or high',
    'open' => 'Nothing open'
  }.freeze

  # `due_date` is a date, so the label never carries a time. `today` comes from the query
  # result so the header counts and every row agree on what "today" means.
  # Returns { text:, overdue: } or nil when the issue has no due date.
  def dashboard_due_label(issue, today)
    due = issue.due_date
    return nil unless due

    if due == today
      { text: 'Today', overdue: false }
    elsif due < today
      { text: "Overdue · #{(today - due).to_i}d", overdue: true }
    else
      { text: due.strftime('%a %b %-d'), overdue: false }
    end
  end

  # Builds a dashboard URL, leaving defaults (filter=today, mine off) out of the query string.
  def dashboard_filter_path(dashboard, filter:, mine:)
    params = {}
    params[:filter] = filter unless filter == DashboardIssuesQuery::DEFAULT_FILTER
    params[:mine] = 1 if mine
    dashboard_path(dashboard, params)
  end

  def priority_dot_class(issue)
    PRIORITY_DOT_CLASSES.fetch(issue.priority, 'bg-gray-500')
  end

  def dashboard_empty_group_message(filter)
    EMPTY_GROUP_MESSAGES.fetch(filter, EMPTY_GROUP_MESSAGES['open'])
  end

  CONTROL_BASE_CLASS = 'inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md whitespace-nowrap ' \
                       'transition-colors cursor-pointer'.freeze

  # Shared look for the filter tabs and the Mine-only toggle.
  def dashboard_control_class(active)
    state = active ? 'bg-foreground border border-stroke text-gray-100' : 'text-gray-500 hover:text-gray-300'
    "#{CONTROL_BASE_CLASS} #{state}"
  end
end
