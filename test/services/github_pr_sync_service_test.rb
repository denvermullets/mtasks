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

  private

  def build_pr_data(title:, body:, head_ref:, number: 1)
    {
      'number' => number,
      'title' => title,
      'body' => body,
      'html_url' => 'https://github.com/denvermullets/mtasks/pull/1',
      'state' => 'open',
      'user' => { 'login' => 'denvermullets' },
      'head' => { 'ref' => head_ref },
      'base' => { 'ref' => 'dev' },
      'merged' => false,
      'merged_at' => nil,
      'closed_at' => nil,
      'created_at' => '2026-04-12T00:00:00Z',
      'updated_at' => '2026-04-12T00:00:00Z'
    }
  end
end
