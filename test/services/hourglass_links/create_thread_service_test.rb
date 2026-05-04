require 'test_helper'

module HourglassLinks
  class CreateThreadServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @user = User.create!(name: 'CT', email: 'create_thread@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'WS', owner: @user)
      @team = @workspace.teams.create!(name: 'T', identifier: 'CTL')
      @team.team_memberships.create!(user: @user)
      @lane = @team.lanes.create!(name: 'L', position: 0)
      @issue = @team.issues.create!(title: 'I', lane: @lane, creator: @user)
      @integration = @workspace.hourglass_integrations.create!(
        hourglass_server_id: 'srv', base_url: 'https://hg.test', api_token: 'tok',
        webhook_secret: 'wh', connected_by_user: @user
      )
    end

    test 'persists an issue_thread link with the pasted thread id' do
      result = HourglassLinks::CreateThreadService.call(
        issue: @issue,
        hourglass_thread_id: 'T_root',
        integration: @integration,
        current_user: @user
      )

      assert_nil result.error
      assert_predicate result.link, :persisted?
      assert_equal 'issue_thread', result.link.link_type
      assert_equal 'T_root', result.link.hourglass_thread_id
      assert_equal @issue.id, result.link.mtasks_issue_id
      assert result.link.active?
    end

    test 'returns error when thread id is blank' do
      result = HourglassLinks::CreateThreadService.call(
        issue: @issue,
        hourglass_thread_id: '   ',
        integration: @integration,
        current_user: @user
      )

      assert_match(/required/i, result.error)
    end

    test 'enqueues HourglassNotifyThreadLinkCreatedJob by default' do
      assert_enqueued_with(job: HourglassNotifyThreadLinkCreatedJob) do
        HourglassLinks::CreateThreadService.call(
          issue: @issue, hourglass_thread_id: 'T_OK',
          integration: @integration, current_user: @user
        )
      end
    end

    test 'skips notify when notify_outbound: false' do
      assert_no_enqueued_jobs(only: HourglassNotifyThreadLinkCreatedJob) do
        HourglassLinks::CreateThreadService.call(
          issue: @issue, hourglass_thread_id: 'T_QUIET',
          integration: @integration, current_user: @user,
          notify_outbound: false
        )
      end
    end
  end
end
