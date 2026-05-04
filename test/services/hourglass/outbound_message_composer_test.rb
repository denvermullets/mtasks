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

    test 'issue.created body uses identifier title and actor' do
      body = OutboundMessageComposer.call(event_type: 'issue.created', issue: @issue, actor: @user)
      assert_equal "#{@issue.identifier} created by Ryan: Ship feature", body
    end

    test 'issue.status_changed resolves lane names' do
      version = fake_version('lane_id' => [@backlog.id, @in_progress.id])
      body = OutboundMessageComposer.call(
        event_type: 'issue.status_changed', issue: @issue, actor: @user, version: version
      )
      assert_equal "#{@issue.identifier} moved Backlog → In Progress by Ryan", body
    end

    test 'issue.assigned handles unassigned → user' do
      version = fake_version('assignee_id' => [nil, @other.id])
      body = OutboundMessageComposer.call(
        event_type: 'issue.assigned', issue: @issue, actor: @user, version: version
      )
      assert_equal "#{@issue.identifier} reassigned Unassigned → Sam by Ryan", body
    end

    test 'issue.priority_changed maps integer enum values to labels' do
      version = fake_version('priority' => [Issue.priorities['low'], Issue.priorities['urgent']])
      body = OutboundMessageComposer.call(
        event_type: 'issue.priority_changed', issue: @issue, actor: @user, version: version
      )
      assert_equal "#{@issue.identifier} priority Low → Urgent by Ryan", body
    end

    test 'issue.updated body falls back to generic update' do
      body = OutboundMessageComposer.call(event_type: 'issue.updated', issue: @issue, actor: @user)
      assert_equal "#{@issue.identifier} updated by Ryan", body
    end

    test 'change body without version data falls back gracefully' do
      version = fake_version({})
      body = OutboundMessageComposer.call(
        event_type: 'issue.status_changed', issue: @issue, actor: @user, version: version
      )
      assert_equal "#{@issue.identifier} moved by Ryan", body
    end
  end
end
