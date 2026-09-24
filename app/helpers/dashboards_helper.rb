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
    'hot' => 'No urgent or high-priority issues',
    'open' => 'No open issues'
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

  # The filter tab and Mine-only state as query params, leaving defaults (filter=today, mine off)
  # out. Shared by the tab links and the header search form's hidden fields.
  def dashboard_view_params(filter:, mine:)
    params = {}
    params[:filter] = filter unless filter == DashboardIssuesQuery::DEFAULT_FILTER
    params[:mine] = 1 if mine
    params
  end

  # Builds a dashboard URL for a tab / Mine-only link. Keeps the current search and team
  # filter so switching tabs never resets them (blank values are dropped, see DashboardPage).
  def dashboard_filter_path(dashboard, filter:, mine:)
    kept = request.query_parameters.slice('q', 'team').compact_blank
    dashboard_path(dashboard, kept.merge(dashboard_view_params(filter: filter, mine: mine)))
  end

  def priority_dot_class(issue)
    PRIORITY_DOT_CLASSES.fetch(issue.priority, 'bg-gray-500')
  end

  # "Nothing due today assigned to you 🎉": the Mine-only suffix goes before the emoji.
  def dashboard_empty_group_message(filter, mine: false)
    message = EMPTY_GROUP_MESSAGES.fetch(filter, EMPTY_GROUP_MESSAGES['open'])
    message += ' assigned to you' if mine
    message += ' 🎉' if filter == 'today'
    message
  end

  CONTROL_BASE_CLASS = 'inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md whitespace-nowrap ' \
                       'transition-colors cursor-pointer'.freeze

  # Shared look for the filter tabs and the Mine-only toggle.
  def dashboard_control_class(active)
    state = active ? 'bg-foreground border border-stroke text-gray-100' : 'text-gray-500 hover:text-gray-300'
    "#{CONTROL_BASE_CLASS} #{state}"
  end
end
