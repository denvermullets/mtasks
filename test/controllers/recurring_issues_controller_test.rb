require 'test_helper'

class RecurringIssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member = User.create!(name: 'Member', email: "ric-#{SecureRandom.hex(4)}@example.com", password: 'password')
    @outsider = User.create!(name: 'Outsider', email: "rio-#{SecureRandom.hex(4)}@example.com", password: 'password')
    @workspace = Workspace.create!(name: 'Acme', owner: @member)
    @team = @workspace.teams.create!(name: 'Engineering', identifier: 'RIC')
    @team.team_memberships.create!(user: @member)
  end

  def valid_params(**overrides)
    { recurring_issue: { title: 'Deploy', frequency: 'weekly', interval: '1', weekday: '5',
                         priority: 'high', starts_on: Date.current.iso8601, label_ids: [''] }.merge(overrides) }
  end

  test 'a member sees the list and the form' do
    sign_in_as(@member)

    get team_recurring_issues_path(@team)
    assert_response :success

    get new_team_recurring_issue_path(@team)
    assert_response :success
  end

  test 'a new schedule defaults to the creator time zone preference' do
    @member.update!(settings: { 'time_zone' => 'Eastern Time (US & Canada)' })
    sign_in_as(@member)

    get new_team_recurring_issue_path(@team)
    assert_select 'select[name=?] option[selected][value=?]', 'recurring_issue[time_zone]', 'Eastern Time (US & Canada)'

    post team_recurring_issues_path(@team), params: valid_params
    assert_equal 'Eastern Time (US & Canada)', @team.recurring_issues.last.time_zone
  end

  test 'a non-member is turned away' do
    sign_in_as(@outsider)
    post team_recurring_issues_path(@team), params: valid_params

    assert_redirected_to root_path
    assert_equal 0, @team.recurring_issues.count
  end

  test 'creating schedules the first occurrence' do
    sign_in_as(@member)

    assert_difference -> { @team.recurring_issues.count }, 1 do
      post team_recurring_issues_path(@team), params: valid_params
    end
    record = @team.recurring_issues.last
    assert_redirected_to team_recurring_issues_path(@team)
    assert_equal @member, record.creator
    assert_equal 5, record.next_run_on.wday
    assert record.high?
  end

  test 'an invalid form re-renders with errors' do
    sign_in_as(@member)
    post team_recurring_issues_path(@team), params: valid_params(title: '')

    assert_response :unprocessable_entity
  end

  test 'updating and deleting' do
    sign_in_as(@member)
    record = @team.recurring_issues.create!(title: 'Deploy', frequency: :daily, next_run_on: Date.current)

    get edit_team_recurring_issue_path(@team, record)
    assert_response :success

    patch team_recurring_issue_path(@team, record),
          params: valid_params(title: 'Ship it', frequency: 'monthly', day_of_month: '1')
    assert_equal 'Ship it', record.reload.title
    assert_equal 1, record.next_run_on.day

    delete team_recurring_issue_path(@team, record)
    assert_not RecurringIssue.exists?(record.id)
  end
end
