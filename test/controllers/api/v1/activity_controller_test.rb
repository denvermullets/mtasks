require 'test_helper'

module Api
  module V1
    class ActivityControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_activity@example.com', password: 'password')
        @workspace = Workspace.create!(name: 'API Workspace', owner: @user)
        @team = @workspace.teams.create!(name: 'API Team', identifier: 'APA')
        @team.team_memberships.create!(user: @user)
        @backlog = @team.lanes.create!(name: 'Backlog', position: 0)
        @doing = @team.lanes.create!(name: 'Doing', position: 1)
        @issue = @team.issues.create!(title: 'Original', lane: @backlog, creator: @user)
        @headers = api_headers_for(@user)
      end

      test 'returns unauthorized without token' do
        get api_v1_team_issue_activity_path(@team, @issue), headers: { 'Content-Type' => 'application/json' }
        assert_response :unauthorized
      end

      test 'returns field changes with resolved names' do
        PaperTrail.request(whodunnit: @user.id.to_s) do
          @issue.update!(title: 'Renamed', lane: @doing, assignee: @user, priority: :high)
        end

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        assert_response :success
        body = response.parsed_body
        assert_equal 1, body.size
        entry = body.first
        assert_equal 'version', entry['type']
        assert_equal 'update', entry['event']
        assert_equal({ 'id' => @user.id, 'name' => 'API User' }, entry['actor'])

        by_field = entry['changes'].index_by { |c| c['field'] }
        assert_equal({ 'from' => 'Original', 'to' => 'Renamed' }, by_field['title'].slice('from', 'to'))
        assert_equal({ 'id' => @backlog.id, 'name' => 'Backlog' }, by_field['lane_id']['from'])
        assert_equal({ 'id' => @doing.id, 'name' => 'Doing' }, by_field['lane_id']['to'])
        assert_nil by_field['assignee_id']['from']
        assert_equal({ 'id' => @user.id, 'name' => 'API User' }, by_field['assignee_id']['to'])
        assert_equal 'high', by_field['priority']['to']
      end

      test 'description matches what the web shows' do
        @issue.update!(lane: @doing)
        version = @issue.versions.where(event: 'update').last

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        assert_equal VersionDescriptionService.call(version), response.parsed_body.first['description']
        assert_includes response.parsed_body.first['description'], 'Doing'
      end

      test 'entries are ordered oldest first' do
        @issue.update!(title: 'One')
        @issue.update!(title: 'Two')

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        ids = response.parsed_body.pluck('id')
        assert_equal ids.sort, ids
        assert_equal 2, ids.size
      end

      test 'adding and removing a dependency produce dependency entries' do
        other = @team.issues.create!(title: 'Other', lane: @backlog, creator: @user)
        PaperTrail.request(whodunnit: @user.id.to_s) do
          dep = IssueDependencies::Link.call(issue: @issue, target: other, direction: 'blocked_by')
          dep.destroy
        end

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        deps = response.parsed_body.select { |e| e['type'] == 'dependency' }
        assert_equal %w[create destroy], deps.pluck('event')
        deps.each do |e|
          assert_equal 'blocks', e['kind']
          assert_equal 'blocked_by', e['direction']
          assert_equal other.id, e['other_issue']['id']
          assert_equal other.identifier, e['other_issue']['identifier']
          assert_equal @user.id, e['actor']['id']
          assert_includes e['description'], 'dependency'
        end
      end

      test 'a comment produces a comment entry' do
        comment = @issue.comments.create!(body: 'hello', user: @user)
        comment.replies.create!(body: 'reply', user: @user, issue: @issue)

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        entries = response.parsed_body.select { |e| e['type'] == 'comment' }
        assert_equal 1, entries.size
        assert_equal comment.id, entries.first['id']
        assert_equal 'hello', entries.first['comment']['body']
      end

      test 'referencing the issue produces a reference entry' do
        other = @team.issues.create!(title: 'Mentions', lane: @backlog, creator: @user)
        IssueReferenceService.call(source_issue: other, text: "see #{@issue.identifier}",
                                   source_type: 'comment', user: @user)

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        entry = response.parsed_body.find { |e| e['type'] == 'reference' }
        assert_equal other.id, entry['source_issue']['id']
        assert_equal 'comment', entry['source_type']
        assert_equal @user.id, entry['user']['id']
      end

      test 'entry types are mixed into oldest-first order' do
        travel_to 3.hours.ago do
          @issue.update!(title: 'First')
        end
        travel_to 2.hours.ago do
          @issue.comments.create!(body: 'second', user: @user)
        end
        travel_to 1.hour.ago do
          other = @team.issues.create!(title: 'Other', lane: @backlog, creator: @user)
          IssueDependencies::Link.call(issue: @issue, target: other, direction: 'blocking')
        end

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        assert_equal %w[version comment dependency], response.parsed_body.pluck('type')
      end

      test 'types filters to the listed types' do
        @issue.update!(title: 'Changed')
        @issue.comments.create!(body: 'hi', user: @user)

        get api_v1_team_issue_activity_path(@team, @issue), params: { types: 'comments' }, headers: @headers
        assert_equal ['comment'], response.parsed_body.pluck('type')

        get api_v1_team_issue_activity_path(@team, @issue), params: { types: 'comments,versions' }, headers: @headers
        assert_equal %w[version comment], response.parsed_body.pluck('type')
      end

      test 'since returns only newer entries' do
        travel_to 2.days.ago do
          @issue.comments.create!(body: 'old', user: @user)
        end
        @issue.comments.create!(body: 'new', user: @user)

        get api_v1_team_issue_activity_path(@team, @issue),
            params: { since: 1.day.ago.iso8601 }, headers: @headers
        bodies = response.parsed_body.map { |e| e.dig('comment', 'body') }
        assert_equal ['new'], bodies
      end

      test 'limit and before_id page through history without gaps or repeats' do
        # Same timestamp for several entries and mixed types exercise the tie-break.
        stamp = 1.hour.ago
        travel_to stamp do
          3.times { |i| @issue.comments.create!(body: "c#{i}", user: @user) }
          @issue.update!(title: 'Moved')
        end
        @issue.comments.create!(body: 'latest', user: @user)

        get api_v1_team_issue_activity_path(@team, @issue), headers: @headers
        full = response.parsed_body.pluck('cursor')
        assert_equal 5, full.size

        paged = []
        before = nil
        loop do
          params = { limit: 2 }
          params[:before_id] = before if before
          get api_v1_team_issue_activity_path(@team, @issue), params: params, headers: @headers
          assert_response :success
          paged.unshift(*response.parsed_body.pluck('cursor'))
          before = response.headers['X-Next-Before-Id']
          break unless before
        end
        assert_equal full, paged
      end

      test 'before_id for an unknown entry is not found' do
        get api_v1_team_issue_activity_path(@team, @issue), params: { before_id: 'comment:0' }, headers: @headers
        assert_response :not_found
      end

      test 'returns not found for a team outside the token' do
        other = User.create!(name: 'Other', email: 'other_activity@example.com', password: 'password')
        ws = Workspace.create!(name: 'Other WS', owner: other)
        team = ws.teams.create!(name: 'Other', identifier: 'OTA')
        lane = team.lanes.create!(name: 'Backlog', position: 0)
        issue = team.issues.create!(title: 'Theirs', lane: lane, creator: other)

        get api_v1_team_issue_activity_path(team, issue), headers: @headers
        assert_response :not_found
      end

      test 'returns not found for an issue from another team' do
        other_team = @workspace.teams.create!(name: 'Second', identifier: 'APB')
        other_team.team_memberships.create!(user: @user)
        lane = other_team.lanes.create!(name: 'Backlog', position: 0)
        issue = other_team.issues.create!(title: 'Elsewhere', lane: lane, creator: @user)

        get api_v1_team_issue_activity_path(@team, issue), headers: @headers
        assert_response :not_found
      end
    end
  end
end
