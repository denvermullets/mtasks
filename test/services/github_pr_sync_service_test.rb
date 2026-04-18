require 'test_helper'

class GithubPrSyncServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'sync_test@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = Team.create!(name: 'Hourglass', identifier: 'HOUR', workspace: @workspace)
    @lane = Lane.create!(name: 'Backlog', team: @team, position: 0)
    @issue = Issue.create!(title: 'Test Issue', team: @team, lane: @lane, creator: @user, team_number: 4)

    @installation = GithubInstallation.create!(
      installation_id: '67890',
      workspace: @workspace
    )
    @subscription = GithubRepositorySubscription.create!(
      team: @team,
      github_installation: @installation,
      github_repo_full_name: 'denvermullets/mtasks'
    )

    @service = GithubPrSyncService.new(@subscription)
  end

  test 'links issue when shortcode is only in branch name' do
    pr_data = build_pr_data(
      title: 'Fix auth bug',
      body: 'No shortcodes here',
      head_ref: 'feature/hour-4-fix-auth'
    )

    assert_difference 'IssuePullRequest.count', 1 do
      @service.sync_pull_request(pr_data)
    end

    pull_request = @subscription.pull_requests.find_by(pr_number: 1)
    assert_includes pull_request.issues, @issue
  end

  test 'does not create duplicate links when shortcode in title and branch' do
    pr_data = build_pr_data(
      title: 'Fix HOUR-4 auth bug',
      body: '',
      head_ref: 'feature/hour-4-fix-auth'
    )

    assert_difference 'IssuePullRequest.count', 1 do
      @service.sync_pull_request(pr_data)
    end
  end

  test 'determine_trigger maps webhook actions correctly' do
    cases = [['opened', false, 'pr_opened'], ['reopened', false, 'pr_opened'],
             ['closed', true, 'pr_merged'], ['closed', false, 'pr_closed'],
             ['edited', false, nil], ['synchronize', false, nil]]
    cases.each do |action, merged, expected|
      result = @service.send(:determine_trigger, action, PullRequest.new(merged: merged))
      msg = "action=#{action} merged=#{merged}"
      expected.nil? ? assert_nil(result, msg) : assert_equal(expected, result, msg)
    end
  end

  test 'pr_opened rule moves linked issues to configured lane' do
    target = Lane.create!(name: 'In Progress', team: @team, position: 1)
    create_rule(trigger: 'pr_opened', lane: target)

    @service.sync_pull_request(build_pr_data(title: 'HOUR-4 work'), action: 'opened')

    assert_equal target.id, @issue.reload.lane_id
  end

  test 'pr_merged rule with exact branch match moves issues and sets completed_at for Done' do
    target = Lane.create!(name: 'Done', team: @team, position: 2)
    create_rule(trigger: 'pr_merged', branch_pattern: 'main', lane: target)

    @service.sync_pull_request(build_pr_data(base_ref: 'main', merged: true), action: 'closed')

    @issue.reload
    assert_equal target.id, @issue.lane_id
    assert_not_nil @issue.completed_at
  end

  test 'pr_merged rules are scoped per branch pattern' do
    staging_lane = Lane.create!(name: 'Staging', team: @team, position: 1)
    main_lane = Lane.create!(name: 'Main', team: @team, position: 2)
    create_rule(trigger: 'pr_merged', branch_pattern: 'staging', lane: staging_lane)
    create_rule(trigger: 'pr_merged', branch_pattern: 'main', lane: main_lane)

    @service.sync_pull_request(build_pr_data(base_ref: 'staging', merged: true), action: 'closed')

    assert_equal staging_lane.id, @issue.reload.lane_id
  end

  test 'pr_merged rule matches glob branch pattern' do
    target = Lane.create!(name: 'Released', team: @team, position: 1)
    create_rule(trigger: 'pr_merged', branch_pattern: 'release/*', lane: target)

    @service.sync_pull_request(build_pr_data(base_ref: 'release/v1.2', merged: true), action: 'closed')

    assert_equal target.id, @issue.reload.lane_id
  end

  test 'pr_merged with no matching branch rule does not move issues' do
    done = Lane.create!(name: 'Done', team: @team, position: 2)
    create_rule(trigger: 'pr_merged', branch_pattern: 'main', lane: done)

    @service.sync_pull_request(build_pr_data(base_ref: 'staging', merged: true), action: 'closed')

    assert_equal @lane.id, @issue.reload.lane_id
  end

  test 'pr_closed rule moves issues when PR closed without merge' do
    target = Lane.create!(name: 'Canceled', team: @team, position: 1)
    create_rule(trigger: 'pr_closed', lane: target)

    @service.sync_pull_request(build_pr_data, action: 'closed')

    assert_equal target.id, @issue.reload.lane_id
  end

  test 'no automation rules configured is a no-op' do
    assert_nothing_raised do
      @service.sync_pull_request(build_pr_data, action: 'opened')
    end
    assert_equal @lane.id, @issue.reload.lane_id
  end

  test 'issue already in target lane does not trigger a save' do
    create_rule(trigger: 'pr_opened', lane: @lane)

    original_updated_at = @issue.updated_at
    travel 1.second
    @service.sync_pull_request(build_pr_data, action: 'opened')

    assert_equal original_updated_at.to_i, @issue.reload.updated_at.to_i
  end

  test 'all linked issues move when multiple are referenced' do
    second_issue = Issue.create!(title: 'Other', team: @team, lane: @lane, creator: @user, team_number: 5)
    target = Lane.create!(name: 'In Progress', team: @team, position: 1)
    create_rule(trigger: 'pr_opened', lane: target)

    @service.sync_pull_request(build_pr_data(title: 'HOUR-4 HOUR-5'), action: 'opened')

    assert_equal target.id, @issue.reload.lane_id
    assert_equal target.id, second_issue.reload.lane_id
  end

  test 'moving out of Done clears completed_at via apply_lane_timestamps!' do
    done = Lane.create!(name: 'Done', team: @team, position: 2)
    in_progress = Lane.create!(name: 'In Progress', team: @team, position: 1)
    create_rule(trigger: 'pr_merged', branch_pattern: 'main', lane: done)
    create_rule(trigger: 'pr_opened', lane: in_progress)

    @service.sync_pull_request(build_pr_data(base_ref: 'main', merged: true, number: 10), action: 'closed')
    assert_not_nil @issue.reload.completed_at

    @service.sync_pull_request(build_pr_data(number: 11), action: 'opened')

    assert_nil @issue.reload.completed_at
    assert_equal in_progress.id, @issue.lane_id
  end

  private

  def create_rule(trigger:, lane:, branch_pattern: nil)
    PrAutomationRule.create!(
      github_repository_subscription: @subscription,
      trigger: trigger,
      branch_pattern: branch_pattern,
      lane: lane
    )
  end

  def build_pr_data(**opts)
    {
      'number' => opts.fetch(:number, 1),
      'title' => opts.fetch(:title, 'HOUR-4 work'),
      'body' => opts.fetch(:body, ''),
      'html_url' => 'https://github.com/denvermullets/mtasks/pull/1',
      'state' => opts.fetch(:state, 'open'),
      'user' => { 'login' => 'denvermullets' },
      'head' => { 'ref' => opts.fetch(:head_ref, 'feature/hour-4') },
      'base' => { 'ref' => opts.fetch(:base_ref, 'dev') },
      'merged' => opts.fetch(:merged, false),
      'merged_at' => nil,
      'closed_at' => nil,
      'created_at' => '2026-04-12T00:00:00Z',
      'updated_at' => '2026-04-12T00:00:00Z'
    }
  end
end
