require 'test_helper'

class PrAutomationRuleTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'pr_auto_rule@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'PRT')
    @installation = GithubInstallation.create!(workspace: @workspace, installation_id: 99_999)
    @subscription = GithubRepositorySubscription.create!(
      team: @team,
      github_installation: @installation,
      github_repo_full_name: 'owner/repo'
    )
    @lane = @team.lanes.create!(name: 'In Progress', position: 0)
  end

  # Trigger validations

  test 'valid with pr_opened trigger' do
    rule = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      trigger: 'pr_opened',
      lane: @lane
    )
    assert rule.valid?
  end

  test 'valid with pr_closed trigger' do
    rule = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      trigger: 'pr_closed',
      lane: @lane
    )
    assert rule.valid?
  end

  test 'valid with pr_merged trigger and branch_pattern' do
    rule = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      trigger: 'pr_merged',
      branch_pattern: 'main',
      lane: @lane
    )
    assert rule.valid?
  end

  test 'invalid with unknown trigger' do
    rule = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      trigger: 'pr_reviewed',
      lane: @lane
    )
    assert_not rule.valid?
    assert_includes rule.errors[:trigger], 'is not included in the list'
  end

  test 'invalid without trigger' do
    rule = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      lane: @lane
    )
    assert_not rule.valid?
    assert_includes rule.errors[:trigger], "can't be blank"
  end

  # Branch pattern validations

  test 'pr_merged requires branch_pattern' do
    rule = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      trigger: 'pr_merged',
      lane: @lane
    )
    assert_not rule.valid?
    assert_includes rule.errors[:branch_pattern], "can't be blank"
  end

  test 'pr_opened rejects branch_pattern' do
    rule = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      trigger: 'pr_opened',
      branch_pattern: 'main',
      lane: @lane
    )
    assert_not rule.valid?
    assert_includes rule.errors[:branch_pattern], 'must be blank'
  end

  test 'pr_closed rejects branch_pattern' do
    rule = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      trigger: 'pr_closed',
      branch_pattern: 'main',
      lane: @lane
    )
    assert_not rule.valid?
    assert_includes rule.errors[:branch_pattern], 'must be blank'
  end

  # Lane-team consistency

  test 'lane must belong to the same team as subscription' do
    other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
    other_lane = other_team.lanes.create!(name: 'Other Lane', position: 0)

    rule = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      trigger: 'pr_opened',
      lane: other_lane
    )
    assert_not rule.valid?
    assert_includes rule.errors[:lane], 'must belong to the same team as the subscription'
  end

  # Uniqueness

  test 'duplicate trigger and branch_pattern for same subscription is invalid' do
    PrAutomationRule.create!(
      github_repository_subscription: @subscription,
      trigger: 'pr_merged',
      branch_pattern: 'main',
      lane: @lane
    )

    duplicate = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      trigger: 'pr_merged',
      branch_pattern: 'main',
      lane: @lane
    )
    assert_not duplicate.valid?
  end

  test 'same trigger with different branch_pattern is valid' do
    PrAutomationRule.create!(
      github_repository_subscription: @subscription,
      trigger: 'pr_merged',
      branch_pattern: 'main',
      lane: @lane
    )

    release_lane = @team.lanes.create!(name: 'Staging', position: 1)
    different = PrAutomationRule.new(
      github_repository_subscription: @subscription,
      trigger: 'pr_merged',
      branch_pattern: 'release/*',
      lane: release_lane
    )
    assert different.valid?
  end

  # Dependent destroy

  test 'destroying subscription destroys its automation rules' do
    PrAutomationRule.create!(
      github_repository_subscription: @subscription,
      trigger: 'pr_opened',
      lane: @lane
    )

    assert_difference 'PrAutomationRule.count', -1 do
      @subscription.destroy!
    end
  end
end
