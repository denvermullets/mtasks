require 'test_helper'

module Hourglass
  class OutboundMessageComposerTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: 'Ryan', email: 'ryan_omc@example.com', password: 'password')
      @other = User.create!(name: 'Sam', email: 'sam_omc@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'WS', owner: @user)
      @team = @workspace.teams.create!(name: 'T', identifier: 'OMC')
      @team.team_memberships.create!(user: @user)
      @project = @team.projects.create!(name: 'Proj')
      @backlog = @team.lanes.create!(name: 'Backlog', position: 1)
      @in_progress = @team.lanes.create!(name: 'In Progress', position: 2)
      @issue = @team.issues.create!(title: 'Ship feature', lane: @backlog, project: @project, creator: @user)
    end

    def fake_version(changes)
      Struct.new(:object_changes, :event).new(changes, 'update')
    end

    test 'returns body and data hash' do
      result = OutboundMessageComposer.call(event_type: 'issue.created', issue: @issue, actor: @user)
      assert_kind_of Hash, result
      assert result.key?(:body)
      assert result.key?(:data)
    end

    test 'issue.created data carries identifier, title, actor info, and source_url' do
      result = OutboundMessageComposer.call(event_type: 'issue.created', issue: @issue, actor: @user)
      data = result[:data]
      assert_equal 'mtasks', data[:source]
      assert_equal 'issue.created', data[:event_type]
      assert_equal 'ryan_omc@example.com', data[:actor_email]
      assert_equal 'Ryan', data[:actor_name]
      assert_equal 'ryan_omc', data[:actor_username]
      assert_equal @issue.id, data[:issue_id]
      assert_equal @issue.identifier, data[:identifier]
      assert_equal 'Ship feature', data[:title]
      assert_equal 'OMC', data[:team_slug]
      assert_equal 'Proj', data[:project_name]
      assert_equal 'Backlog', data[:status_lane_name]
      assert_match(%r{\Ahttp://[^/]+/teams/#{@team.id}/issues/#{@issue.id}\z}, data[:source_url])
    end

    test 'issue.created fallback body retains the legacy format' do
      result = OutboundMessageComposer.call(event_type: 'issue.created', issue: @issue, actor: @user)
      assert_equal "#{@issue.identifier} created by Ryan: Ship feature", result[:body]
    end

    test 'issue.created includes assignee data when present' do
      @issue.update!(assignee: @other)
      result = OutboundMessageComposer.call(event_type: 'issue.created', issue: @issue, actor: @user)
      data = result[:data]
      assert_equal 'sam_omc@example.com', data[:assignee_email]
      assert_equal 'Sam', data[:assignee_name]
      assert_equal 'sam_omc', data[:assignee_username]
    end

    test 'issue.created omits assignee fields when no assignee' do
      result = OutboundMessageComposer.call(event_type: 'issue.created', issue: @issue, actor: @user)
      data = result[:data]
      assert_nil data[:assignee_email]
      assert_nil data[:assignee_name]
    end

    test 'issue.created includes labels when present' do
      label_a = @team.labels.create!(name: 'bug', color: '#f00')
      label_b = @team.labels.create!(name: 'priority', color: '#fa0')
      @issue.labels << label_a
      @issue.labels << label_b
      result = OutboundMessageComposer.call(event_type: 'issue.created', issue: @issue, actor: @user)
      data = result[:data]
      assert_equal 2, Array(data[:labels]).size
      assert_includes data[:labels].map { |l| l[:name] }, 'bug'
      assert_includes data[:labels].map { |l| l[:name] }, 'priority'
    end

    test 'issue.status_changed data carries from/to lane names' do
      version = fake_version('lane_id' => [@backlog.id, @in_progress.id])
      result = OutboundMessageComposer.call(
        event_type: 'issue.status_changed', issue: @issue, actor: @user, version: version
      )
      assert_equal 'Backlog', result[:data][:from_lane_name]
      assert_equal 'In Progress', result[:data][:to_lane_name]
      assert_equal "#{@issue.identifier} moved Backlog → In Progress by Ryan", result[:body]
    end

    test 'issue.assigned data carries new assignee info' do
      version = fake_version('assignee_id' => [nil, @other.id])
      @issue.update_columns(assignee_id: @other.id)
      result = OutboundMessageComposer.call(
        event_type: 'issue.assigned', issue: @issue, actor: @user, version: version
      )
      assert_equal 'sam_omc@example.com', result[:data][:assignee_email]
      assert_equal 'Sam', result[:data][:assignee_name]
      assert_equal "#{@issue.identifier} reassigned Unassigned → Sam by Ryan", result[:body]
    end

    test 'issue.priority_changed maps integer enum values to lower-case labels' do
      version = fake_version('priority' => [Issue.priorities['low'], Issue.priorities['urgent']])
      result = OutboundMessageComposer.call(
        event_type: 'issue.priority_changed', issue: @issue, actor: @user, version: version
      )
      assert_equal 'urgent', result[:data][:priority]
      assert_equal "#{@issue.identifier} priority Low → Urgent by Ryan", result[:body]
    end

    test 'issue.updated returns generic fallback body and base data' do
      result = OutboundMessageComposer.call(event_type: 'issue.updated', issue: @issue, actor: @user)
      assert_equal "#{@issue.identifier} updated by Ryan", result[:body]
      assert_equal 'issue.updated', result[:data][:event_type]
    end

    test 'change body without version data falls back gracefully' do
      version = fake_version({})
      result = OutboundMessageComposer.call(
        event_type: 'issue.status_changed', issue: @issue, actor: @user, version: version
      )
      assert_equal "#{@issue.identifier} moved by Ryan", result[:body]
      assert_nil result[:data][:from_lane_name]
      assert_nil result[:data][:to_lane_name]
    end
  end
end
