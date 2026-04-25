require 'test_helper'

class DisplayOptionsServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'display_opts@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Test Team', identifier: 'TST')
    @team.team_memberships.create!(user: @user)
  end

  test 'parses comma-separated project_ids into integer array' do
    options = DisplayOptionsService.call({ project_ids: '3,7,12' }, @user, @team)

    assert_equal [3, 7, 12], options[:project_ids]
  end

  test 'returns nil project_ids when param is absent' do
    options = DisplayOptionsService.call({}, @user, @team)

    assert_nil options[:project_ids]
  end

  test 'returns nil project_ids when param is blank' do
    options = DisplayOptionsService.call({ project_ids: '' }, @user, @team)

    assert_nil options[:project_ids]
  end

  test 'ignores blank ids in the comma list' do
    options = DisplayOptionsService.call({ project_ids: '5,,9' }, @user, @team)

    assert_equal [5, 9], options[:project_ids]
  end

  test 'parses lane_ids, assignee_ids, label_ids as integer arrays' do
    options = DisplayOptionsService.call(
      { lane_ids: '1,2', assignee_ids: '4', label_ids: '7,8' }, @user, @team
    )

    assert_equal [1, 2], options[:lane_ids]
    assert_equal [4], options[:assignee_ids]
    assert_equal [7, 8], options[:label_ids]
  end

  test 'parses priority as a string array' do
    options = DisplayOptionsService.call({ priority: 'urgent,high' }, @user, @team)

    assert_equal %w[urgent high], options[:priority]
  end

  test 'returns nil for absent multi-filter params' do
    options = DisplayOptionsService.call({}, @user, @team)

    assert_nil options[:lane_ids]
    assert_nil options[:assignee_ids]
    assert_nil options[:label_ids]
    assert_nil options[:priority]
  end
end
