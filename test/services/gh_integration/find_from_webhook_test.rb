require 'test_helper'

module GhIntegration
  class FindFromWebhookTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: 'Test User', email: 'webhook_test@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
      @team = Team.create!(name: 'Hourglass', identifier: 'HOUR', workspace: @workspace)
      @lane = Lane.create!(name: 'Backlog', team: @team, position: 0)
      @issue = Issue.create!(title: 'Test Issue', team: @team, lane: @lane, creator: @user, team_number: 4)

      @installation = GithubInstallation.create!(
        installation_id: '12345',
        workspace: @workspace
      )
      @subscription = GithubRepositorySubscription.create!(
        team: @team,
        github_installation: @installation,
        github_repo_full_name: 'denvermullets/mtasks'
      )
    end

    test 'finds subscription when shortcode is only in branch name' do
      pr_data = {
        'number' => 1,
        'title' => 'Fix auth bug',
        'body' => 'Some description without shortcodes',
        'head' => { 'ref' => 'feature/hour-4-fix-auth' }
      }

      result = GhIntegration::FindFromWebhook.call(
        installation_id: '12345',
        repo_full_name: 'denvermullets/mtasks',
        pr_data: pr_data
      )

      assert_includes result, @subscription
    end

    test 'does not return duplicate subscriptions when shortcode in title and branch' do
      pr_data = {
        'number' => 2,
        'title' => 'Fix HOUR-4 auth bug',
        'body' => '',
        'head' => { 'ref' => 'feature/hour-4-fix-auth' }
      }

      result = GhIntegration::FindFromWebhook.call(
        installation_id: '12345',
        repo_full_name: 'denvermullets/mtasks',
        pr_data: pr_data
      )

      assert_equal 1, result.count
      assert_includes result, @subscription
    end

    test 'returns empty when no shortcodes found anywhere' do
      pr_data = {
        'number' => 3,
        'title' => 'Update readme',
        'body' => 'Just docs',
        'head' => { 'ref' => 'docs/update-readme' }
      }

      result = GhIntegration::FindFromWebhook.call(
        installation_id: '12345',
        repo_full_name: 'denvermullets/mtasks',
        pr_data: pr_data
      )

      assert_equal [], result
    end
  end
end
