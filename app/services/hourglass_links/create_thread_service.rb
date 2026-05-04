module HourglassLinks
  class CreateThreadService < Service
    Result = Struct.new(:link, :error, keyword_init: true)

    def initialize(issue:, hourglass_thread_id:, integration:, current_user:, notify_outbound: true)
      @issue = issue
      @hourglass_thread_id = hourglass_thread_id.to_s.strip
      @integration = integration
      @current_user = current_user
      @notify_outbound = notify_outbound
    end

    def call
      return Result.new(error: 'Thread ID is required.') if @hourglass_thread_id.blank?

      link = HourglassLink.new(
        link_type: 'issue_thread',
        team: @issue.team,
        mtasks_issue: @issue,
        mtasks_issue_identifier: @issue.identifier,
        hourglass_thread_id: @hourglass_thread_id,
        hourglass_integration: @integration,
        created_by_user: @current_user,
        status: 'active'
      )

      if link.save
        HourglassNotifyThreadLinkCreatedJob.perform_later(link.id) if @notify_outbound
        Result.new(link: link)
      else
        Result.new(link: link, error: link.errors.full_messages.to_sentence)
      end
    end
  end
end
