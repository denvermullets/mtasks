require 'test_helper'

# Smoke coverage for the VEK-584 server call sites: one case per feature_id, plus the
# IssuesController#update decomposition, which is the only place where a single request can
# legitimately produce several events and the only place a mistake would double count.
#
# The exhaustive matrix and the payload-contract assertions belong to VEK-586. What this file
# guarantees is that every catalogued server action fires exactly once, with the right
# (feature_id, action), and that nothing user-authored reaches properties.
class VektisTrackingTest < ActionDispatch::IntegrationTest
  include VektisEventTestHelper

  setup do
    @user = User.create!(name: 'Tracking User', email: 'vektis_tracking@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Tracking Workspace', owner: @user)
    @team = @workspace.teams.create!(name: 'Tracking Team', identifier: 'TRK')
    @team.team_memberships.create!(user: @user)
    enable_vektis!(@team)

    @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
    @done = @team.lanes.create!(name: 'Done', position: 1)
    @project = @team.projects.create!(name: 'Tracking Project')
    @label = @team.labels.create!(name: 'bug', color: '#ff0000')
    @issue = @team.issues.create!(title: 'Tracked issue', lane: @backlog, creator: @user)

    sign_in_as(@user)
    clear_enqueued_jobs
  end

  # --- issue lifecycle -------------------------------------------------------------------------

  test 'creating an issue emits issue-create with shape properties only' do
    post team_issues_path(@team), params: {
      issue: { title: 'Brand new', lane_id: @backlog.id, priority: 'high', project_id: @project.id }
    }

    assert_equal [%w[issue-create create]], pairs
    event = event_for('issue-create')
    assert_equal 'feature.used', event['event_type']
    assert_equal 'server', event['properties']['source']
    assert_equal @user.id.to_s, event['user_id']
    assert_equal 'high', event['properties']['priority']
    assert event['properties']['has_project']
    assert_not event['properties']['is_sub_issue']
    assert_not_includes event['properties'].values, 'Brand new'
  end

  test 'creating a sub-issue with labels and a file emits one event per feature' do
    post team_issues_path(@team), params: {
      issue: { title: 'Child', lane_id: @backlog.id, parent_issue_id: @issue.id, label_ids: ['', @label.id] }
    }

    assert_equal [%w[issue-create create], %w[sub-issue link], %w[issue-label apply]], pairs
    assert event_for('issue-create')['properties']['is_sub_issue']
    assert_equal 1, event_for('issue-label')['properties']['count']
  end

  test 'a lane-picker PATCH emits exactly one issue-workflow event and no issue-edit' do
    patch team_issue_path(@team, @issue), params: { issue: { lane_id: @done.id } }

    assert_equal [%w[issue-workflow complete]], pairs
    properties = event_for('issue-workflow')['properties']
    assert_equal 0, properties['from_position']
    assert_equal 1, properties['to_position']
    assert_equal 'forward', properties['direction']
    assert_not_includes properties.keys, 'lane_name'
  end

  test 'moving out of a terminal lane emits reopen' do
    @issue.update!(lane: @done, completed_at: 1.hour.ago)
    clear_enqueued_jobs

    patch team_issue_path(@team, @issue), params: { issue: { lane_id: @backlog.id } }

    assert_equal [%w[issue-workflow reopen]], pairs
    assert_equal 'backward', event_for('issue-workflow')['properties']['direction']
  end

  test 'an edit-form save fans out to one event per feature touched' do
    patch team_issue_path(@team, @issue), params: {
      issue: { title: 'Renamed', lane_id: @done.id, parent_issue_id: '', label_ids: ['', @label.id] }
    }

    assert_equal [%w[issue-workflow complete], %w[issue-label apply], %w[issue-edit update]], pairs
  end

  test 'removing a label through the edit form emits issue-label remove, not apply' do
    @issue.labels << @label
    clear_enqueued_jobs

    patch team_issue_path(@team, @issue), params: { issue: { label_ids: [''] } }

    assert_equal [%w[issue-label remove]], pairs
    assert_equal 1, event_for('issue-label')['properties']['count']
  end

  test 'a save that changes nothing emits nothing' do
    patch team_issue_path(@team, @issue), params: { issue: { title: @issue.title } }

    assert_empty pairs
  end

  test 'deleting an issue emits issue-delete' do
    delete team_issue_path(@team, @issue)

    assert_equal [%w[issue-delete delete]], pairs
  end

  test 'transferring an issue to another team emits issue-transfer' do
    other_team = @workspace.teams.create!(name: 'Other Team', identifier: 'OTH')
    other_team.team_memberships.create!(user: @user)
    other_team.lanes.create!(name: 'Backlog', position: 0)
    clear_enqueued_jobs

    patch team_issue_move_path(@team, @issue), params: { target_team_id: other_team.id }

    assert_equal [%w[issue-transfer move]], pairs
  end

  # --- relations -------------------------------------------------------------------------------

  test 'linking and unlinking a dependency emits issue-dependency' do
    blocker = @team.issues.create!(title: 'Blocker', lane: @backlog, creator: @user)

    post team_issue_issue_dependencies_path(@team, @issue),
         params: { target_issue_id: blocker.id, direction: 'blocked_by' }, as: :turbo_stream
    assert_equal [%w[issue-dependency link]], pairs
    assert_equal 'blocked_by', event_for('issue-dependency')['properties']['direction']
    assert_equal 1, event_for('issue-dependency')['properties']['count']

    clear_enqueued_jobs
    delete team_issue_issue_dependency_path(@team, @issue, blocker.id), as: :turbo_stream
    assert_equal [%w[issue-dependency unlink]], pairs
  end

  test 'bulk-linking dependencies emits one event carrying the count' do
    targets = 3.times.map { |i| @team.issues.create!(title: "Blocked #{i}", lane: @backlog, creator: @user) }
    clear_enqueued_jobs

    post bulk_create_team_issue_issue_dependencies_path(@team, @issue),
         params: { target_issue_ids: targets.map(&:id), direction: 'blocking' }, as: :turbo_stream

    assert_equal [%w[issue-dependency link]], pairs
    assert_equal 3, event_for('issue-dependency')['properties']['count']
  end

  test 'the label picker emits issue-label apply and remove' do
    post team_issue_issue_labels_path(@team, @issue), params: { label_id: @label.id }, as: :turbo_stream
    assert_equal [%w[issue-label apply]], pairs

    clear_enqueued_jobs
    delete team_issue_issue_label_path(@team, @issue, @label.id), as: :turbo_stream
    assert_equal [%w[issue-label remove]], pairs
  end

  # --- planning --------------------------------------------------------------------------------

  test 'project create, update and delete emit project-management' do
    post team_projects_path(@team), params: { project: { name: 'Fresh', priority: 'low' } }
    assert_equal [%w[project-management create]], pairs
    assert_equal 'low', event_for('project-management')['properties']['priority']

    clear_enqueued_jobs
    patch team_project_path(@team, @project), params: { project: { name: 'Renamed' } }
    assert_equal [%w[project-management update]], pairs

    clear_enqueued_jobs
    delete team_project_path(@team, @project)
    assert_equal [%w[project-management delete]], pairs
  end

  test 'adding a project to the roadmap emits roadmap create, and removing it does not' do
    patch team_project_path(@team, @project), params: { project: { roadmap_commitment: 'now' } }
    assert_equal [%w[roadmap create]], pairs

    clear_enqueued_jobs
    patch team_project_path(@team, @project), params: { project: { roadmap_commitment: '' } }
    assert_equal [%w[project-management update]], pairs
  end

  test 'project labels emit project-label' do
    post team_project_project_labels_path(@team, @project), params: { label_id: @label.id }, as: :turbo_stream
    assert_equal [%w[project-label apply]], pairs

    clear_enqueued_jobs
    delete team_project_project_label_path(@team, @project, @label.id), as: :turbo_stream
    assert_equal [%w[project-label remove]], pairs
  end

  test 'removing a project file emits issue-attachment remove scoped by entity' do
    @project.files.attach(io: StringIO.new('hello'), filename: 'notes.txt', content_type: 'text/plain')
    clear_enqueued_jobs

    delete purge_file_team_project_path(@team, @project), params: { file_id: @project.files.first.id }

    assert_equal [%w[issue-attachment remove]], pairs
    properties = event_for('issue-attachment')['properties']
    assert_equal 'project', properties['entity']
    assert_not_includes properties.values, 'notes.txt'
  end

  test 'team label CRUD emits label-management' do
    post team_labels_path(@team), params: { label: { name: 'chore', color: '#00ff00' } }, as: :turbo_stream
    assert_equal [%w[label-management create]], pairs

    clear_enqueued_jobs
    patch team_label_path(@team, @label), params: { label: { name: 'defect' } }, as: :turbo_stream
    assert_equal [%w[label-management update]], pairs

    clear_enqueued_jobs
    delete team_label_path(@team, @label), as: :turbo_stream
    assert_equal [%w[label-management delete]], pairs
  end

  test 'lane create, reorder and delete emit lane-management with positions only' do
    next_position = @team.lanes.maximum(:position) + 1

    post team_lanes_path(@team), params: { lane: { name: 'In Review', color: '#0000ff' } }, as: :turbo_stream
    assert_equal [%w[lane-management create]], pairs
    assert_equal next_position, event_for('lane-management')['properties']['to_position']

    clear_enqueued_jobs
    patch team_lane_path(@team, @done), params: { lane: { position: 0 } }, as: :turbo_stream
    assert_equal [%w[lane-management update]], pairs
    properties = event_for('lane-management')['properties']
    assert_equal 'backward', properties['direction']
    assert_not_includes properties.values, 'Done'

    clear_enqueued_jobs
    delete team_lane_path(@team, @done), params: { target_lane_id: @backlog.id }, as: :turbo_stream
    assert_equal [%w[lane-management delete]], pairs
  end

  # --- collaboration ---------------------------------------------------------------------------

  test 'issue comments emit comment create and delete with depth' do
    post team_issue_comments_path(@team, @issue), params: { comment: { body: 'secret content' } },
                                                  as: :turbo_stream
    assert_equal [%w[comment create]], pairs
    event = event_for('comment')
    assert_equal 'issue', event['properties']['entity']
    assert_equal 0, event['properties']['depth']
    assert_not_includes event['properties'].values, 'secret content'

    comment = @issue.comments.last
    clear_enqueued_jobs
    delete team_issue_comment_path(@team, @issue, comment), as: :turbo_stream
    assert_equal [%w[comment delete]], pairs
  end

  test 'a reply carries its nesting depth' do
    parent = @issue.comments.create!(body: 'parent', user: @user)
    clear_enqueued_jobs

    post team_issue_comments_path(@team, @issue),
         params: { comment: { body: 'reply', parent_id: parent.id } }, as: :turbo_stream

    assert_equal 1, event_for('comment')['properties']['depth']
  end

  test 'project and issue discussion comments emit comment create tagged with the tab' do
    post team_project_discussion_comments_path(@team, @project), params: { comment: { body: 'hi' } },
                                                                 as: :turbo_stream
    assert_equal [%w[comment create]], pairs
    assert_equal 'project', event_for('comment')['properties']['entity']
    assert_equal 'discussion', event_for('comment')['properties']['tab']

    clear_enqueued_jobs
    post team_issue_discussion_comments_path(@team, @issue), params: { comment: { body: 'hi' } },
                                                             as: :turbo_stream
    assert_equal 'issue', event_for('comment')['properties']['entity']
  end

  test 'notification read and read_all emit notification' do
    actor = User.create!(name: 'Actor', email: 'vektis_actor@example.com', password: 'password')
    notification = @user.notifications.create!(actor: actor, issue: @issue, action: 'assigned',
                                               message: 'assigned you an issue')
    clear_enqueued_jobs

    patch mark_as_read_notification_path(notification), as: :turbo_stream
    assert_equal [%w[notification read]], pairs

    # Already read: mark_as_read! no-ops, so nothing is emitted a second time.
    clear_enqueued_jobs
    patch mark_as_read_notification_path(notification), as: :turbo_stream
    assert_empty pairs

    @user.notifications.create!(actor: actor, issue: @issue, action: 'commented', message: 'commented')
    clear_enqueued_jobs
    patch mark_all_as_read_notifications_path, as: :turbo_stream
    assert_equal [%w[notification read_all]], pairs
    assert_equal 1, event_for('notification')['properties']['count']
  end

  # --- data movement ---------------------------------------------------------------------------

  test 'a CSV import emits one csv-import event carrying the row count' do
    csv = "Title,Description,Status,Priority,Team\nImported one,,Backlog,high,#{@team.name}\n"
    file = Rack::Test::UploadedFile.new(StringIO.new(csv), 'text/csv', original_filename: 'issues.csv')

    post imports_path, params: { csv_file: file }

    assert_equal [%w[csv-import import]], pairs
    assert_equal 1, event_for('csv-import')['properties']['count']
  end

  test 'a team export emits one team-export event carrying the row count' do
    post team_export_path(@team)

    assert_response :success
    assert_equal [%w[team-export export]], pairs
    assert_equal @team.issues.count, event_for('team-export')['properties']['count']
  end

  # --- taxonomy conformance --------------------------------------------------------------------

  test 'no server event ever carries an unregistered key or a non-scalar value' do
    post team_issues_path(@team), params: {
      issue: { title: 'Shape', lane_id: @backlog.id, priority: 'urgent', label_ids: ['', @label.id] }
    }
    patch team_issue_path(@team, @team.issues.last), params: { issue: { lane_id: @done.id } }
    post team_issue_comments_path(@team, @issue), params: { comment: { body: 'body' } }, as: :turbo_stream

    assert_operator emitted.size, :>=, 4
    emitted.each do |event|
      unknown = event['properties'].keys - Vektis::Taxonomy::PROPERTY_KEYS
      assert_empty unknown, "#{event['feature_id']} carried #{unknown.inspect}"
      assert_includes Vektis::Taxonomy::CATALOG.fetch(event['feature_id']), event['action']
      event['properties'].each_value do |value|
        assert value.is_a?(String) || value.is_a?(Numeric) || [true, false].include?(value)
      end
    end
  end
end
