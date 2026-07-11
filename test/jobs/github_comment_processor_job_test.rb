require 'test_helper'

class GithubCommentProcessorJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(name: 'Ryan', email: 'ryan_gcpj@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'WS', owner: @user)
    @team = @workspace.teams.create!(name: 'Hourglass', identifier: 'HOUR')
    @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
    @in_progress = @team.lanes.create!(name: 'In Progress', position: 1)
    @issue = @team.issues.create!(title: 'Ship it', lane: @backlog, creator: @user, team_number: 4)

    @installation = GithubInstallation.create!(installation_id: '99999', workspace: @workspace)
    @subscription = GithubRepositorySubscription.create!(
      team: @team,
      github_installation: @installation,
      github_repo_full_name: 'denvermullets/mtasks'
    )
    @pull_request = @subscription.pull_requests.create!(
      pr_number: 7, title: 'No shortcode here', state: 'open', head_ref: 'fix/thing', base_ref: 'dev'
    )
  end

  test 'comment referencing an issue links it to the PR' do
    assert_difference 'IssuePullRequest.count', 1 do
      GithubCommentProcessorJob.perform_now(@subscription.id, 7, 'this covers HOUR-4')
    end

    assert_includes @pull_request.reload.issues, @issue
  end

  test 'comment referencing an issue moves it to the pr_opened lane' do
    PrAutomationRule.create!(
      github_repository_subscription: @subscription, trigger: 'pr_opened', lane: @in_progress
    )

    GithubCommentProcessorJob.perform_now(@subscription.id, 7, 'this covers HOUR-4')

    assert_equal @in_progress.id, @issue.reload.lane_id
  end

  test 'comment referencing an already linked issue does not move it again' do
    PrAutomationRule.create!(
      github_repository_subscription: @subscription, trigger: 'pr_opened', lane: @in_progress
    )
    IssuePullRequest.create!(issue: @issue, pull_request: @pull_request)
    in_review = @team.lanes.create!(name: 'In Review', position: 2)
    @issue.update!(lane: in_review)

    GithubCommentProcessorJob.perform_now(@subscription.id, 7, 'still HOUR-4')

    assert_equal in_review.id, @issue.reload.lane_id
  end

  test 'comment without an issue reference is a no-op' do
    assert_no_difference 'IssuePullRequest.count' do
      GithubCommentProcessorJob.perform_now(@subscription.id, 7, 'looks good to me')
    end
  end
end
