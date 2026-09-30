require 'test_helper'

module Settings
  class SidebarGroupsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(name: 'Ryan', email: "groups-#{SecureRandom.hex(4)}@example.com", password: 'password',
                           settings: { 'appearance' => { 'theme' => 'dusk' } })
      workspace = Workspace.create!(name: 'Groups WS', owner: @user)
      @first_team = workspace.teams.create!(name: 'First', identifier: 'SG1')
      @second_team = workspace.teams.create!(name: 'Second', identifier: 'SG2')
      @first_team.team_memberships.create!(user: @user)
      @second_team.team_memberships.create!(user: @user)
      sign_in_as(@user)
    end

    test 'creates a group without touching other settings' do
      post settings_sidebar_groups_path, params: { name: '  Clients  ' }

      assert_redirected_to settings_path(section: 'team_order')
      @user.reload
      assert_equal(['Clients'], @user.sidebar_groups.map { |g| g['name'] })
      assert_equal 'dusk', @user.theme
    end

    test 'rejects a blank group name' do
      post settings_sidebar_groups_path, params: { name: ' ' }

      assert_empty @user.reload.sidebar_groups
    end

    test 'renames and collapses a group' do
      group_id = create_group('Old')

      patch settings_sidebar_group_path(group_id), params: { name: 'New' }
      patch settings_sidebar_group_path(group_id), params: { collapsed: true }, as: :json

      assert_response :ok
      group = @user.reload.sidebar_groups.first
      assert_equal 'New', group['name']
      assert group['collapsed']
    end

    test 'deleting a group returns its teams to the ungrouped sections' do
      group_id = create_group('Temp')
      patch settings_team_order_path, params: { groups: [{ id: group_id, team_ids: [@second_team.id] }],
                                                owned: [@first_team.id], joined: [] }, as: :json

      delete settings_sidebar_group_path(group_id)

      assert_equal [@first_team, @second_team], @user.reload.sidebar_layout([@first_team, @second_team]).owned
    end

    test 'saves group membership and order from the drag-and-drop layout' do
      first_group = create_group('One')
      second_group = create_group('Two')

      patch settings_team_order_path,
            params: { groups: [{ id: second_group, team_ids: [@second_team.id, 999_999] },
                               { id: first_group, team_ids: [@second_team.id, @first_team.id] }],
                      owned: [@first_team.id, @second_team.id], joined: [] },
            as: :json

      assert_response :ok
      groups = @user.reload.sidebar_groups
      assert_equal(%w[Two One], groups.map { |g| g['name'] })
      assert_equal([[@second_team.id], [@first_team.id]], groups.map { |g| g['team_ids'] })
      assert_empty @user.team_order['owned']
    end

    test 'the sidebar renders groups' do
      group_id = create_group('Clients')
      patch settings_team_order_path, params: { groups: [{ id: group_id, team_ids: [@first_team.id] }],
                                                owned: [@second_team.id], joined: [] }, as: :json

      get settings_path(section: 'team_order')

      assert_response :success
      assert_select '#sidebar_teams [data-controller=sidebar-group]', text: /Clients/
      assert_select '[data-kind=group] [data-team-id=?]', @first_team.id.to_s
    end

    test 'the sidebar hides an empty owned section and moves the new-team link to the first group' do
      group_id = create_group('Everything')
      patch settings_team_order_path, params: { groups: [{ id: group_id, team_ids: [@first_team.id, @second_team.id] }],
                                                owned: [], joined: [] }, as: :json

      get settings_path

      assert_select '#sidebar_teams', text: /Teams you own/, count: 0
      assert_select '#sidebar_teams [data-controller=sidebar-group] a[href=?]', new_team_path
    end

    test 'the mobile drawer renders the same groups with drawer-closing links' do
      group_id = create_group('Clients')
      patch settings_team_order_path, params: { groups: [{ id: group_id, team_ids: [@first_team.id] }],
                                                owned: [@second_team.id], joined: [] }, as: :json

      get settings_path

      assert_select '#sidebar_teams_mobile [data-controller=sidebar-group]', text: /Clients/
      assert_select '#sidebar_teams_mobile a[href=?][data-action=?]', "/teams/#{@first_team.id}/issues",
                    'click->sidebar#close'
    end

    test 'saving the layout re-renders both sidebars' do
      patch settings_team_order_path, params: { owned: [@second_team.id, @first_team.id], joined: [] },
                                      as: :turbo_stream

      assert_select 'turbo-stream[action=replace][target=sidebar_teams]'
      assert_select 'turbo-stream[action=replace][target=sidebar_teams_mobile]'
    end

    private

    def create_group(name)
      post settings_sidebar_groups_path, params: { name: name }
      @user.reload.sidebar_groups.last['id']
    end
  end
end
