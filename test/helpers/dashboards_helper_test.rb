require 'test_helper'

class DashboardsHelperTest < ActionView::TestCase
  TODAY = Date.new(2026, 9, 24) # a Thursday

  test 'dashboard_due_label returns nil without a due date' do
    assert_nil dashboard_due_label(Issue.new(due_date: nil), TODAY)
  end

  test 'dashboard_due_label says Today for issues due today' do
    assert_equal({ text: 'Today', overdue: false, inherited: false },
                 dashboard_due_label(Issue.new(due_date: TODAY), TODAY))
  end

  test 'dashboard_due_label counts overdue days' do
    assert_equal({ text: 'Overdue · 3d', overdue: true, inherited: false },
                 dashboard_due_label(Issue.new(due_date: TODAY - 3), TODAY))
    assert_equal({ text: 'Overdue · 1d', overdue: true, inherited: false },
                 dashboard_due_label(Issue.new(due_date: TODAY - 1), TODAY))
  end

  test 'dashboard_due_label formats future dates as weekday month day' do
    assert_equal({ text: 'Mon Sep 28', overdue: false, inherited: false },
                 dashboard_due_label(Issue.new(due_date: TODAY + 4), TODAY))
  end

  test 'dashboard_due_label falls back to the project due date and flags it as inherited' do
    issue = Issue.new(due_date: nil, project: Project.new(due_date: TODAY + 1))
    assert_equal({ text: 'Fri Sep 25', overdue: false, inherited: true }, dashboard_due_label(issue, TODAY))
  end

  test 'dashboard_due_label prefers the issue due date over the project one' do
    issue = Issue.new(due_date: TODAY, project: Project.new(due_date: TODAY + 1))
    assert_equal({ text: 'Today', overdue: false, inherited: false }, dashboard_due_label(issue, TODAY))
  end

  test 'dashboard_empty_group_message has copy for each filter and falls back for unknown ones' do
    assert_equal 'Nothing due today 🎉', dashboard_empty_group_message('today')
    assert_equal 'Nothing due this week', dashboard_empty_group_message('week')
    assert_equal 'No urgent or high-priority issues', dashboard_empty_group_message('hot')
    assert_equal 'No open issues', dashboard_empty_group_message('open')
    assert_equal 'No open issues', dashboard_empty_group_message('bogus')
  end

  test 'dashboard_empty_group_message adds the Mine-only suffix before the emoji' do
    assert_equal 'Nothing due today assigned to you 🎉', dashboard_empty_group_message('today', mine: true)
    assert_equal 'No open issues assigned to you', dashboard_empty_group_message('open', mine: true)
  end

  test 'priority_dot_class maps priorities to colors' do
    assert_equal 'bg-red-400', priority_dot_class(Issue.new(priority: :urgent))
    assert_equal 'bg-orange-400', priority_dot_class(Issue.new(priority: :high))
    assert_equal 'bg-yellow-400', priority_dot_class(Issue.new(priority: :medium))
    assert_equal 'bg-blue-400', priority_dot_class(Issue.new(priority: :low))
    assert_equal 'bg-gray-500', priority_dot_class(Issue.new(priority: :no_priority))
  end
end
