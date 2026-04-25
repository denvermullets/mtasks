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
end
