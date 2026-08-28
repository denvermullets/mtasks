module HourglassWebhookProcessor
  module Link
    class CreatedHandler < BaseHandler
      def call
        case link_type
        when 'issue_thread'    then handle_issue_thread
        when 'project_channel' then handle_project_channel
        else
          logger.warn("link.created unknown link_type=#{link_type.inspect} (delivery=#{delivery.delivery_id})")
        end
      end

      private

      def link_type
        data['link_type']
      end

      def data
        @data ||= payload['data'].is_a?(Hash) ? payload['data'] : {}
      end

      def handle_issue_thread
        issue = Issue.find_by(id: data['mtasks_issue_id'])
        thread_id = data['hourglass_thread_id'].to_s
        return unless valid_issue_thread?(issue, thread_id)
        return if HourglassLink.for_issue(issue).where(hourglass_thread_id: thread_id).exists?

        result = HourglassLinks::CreateThreadService.call(
          issue: issue, hourglass_thread_id: thread_id,
          integration: integration, current_user: actor_user(issue.team),
          notify_outbound: false
        )
        track_link(result, 'issue')
      end

      def valid_issue_thread?(issue, thread_id)
        return logger.warn("link.created issue_thread missing issue=#{data['mtasks_issue_id']}") && false unless issue
        return logger.warn('link.created issue_thread missing hourglass_thread_id') && false if thread_id.blank?

        true
      end

      def handle_project_channel
        project = Project.find_by(id: data['mtasks_project_id'])
        channel_id = data['hourglass_channel_id'].to_s
        return unless valid_project_channel?(project, channel_id)
        return if HourglassLink.for_project(project).where(hourglass_channel_id: channel_id).exists?

        result = HourglassLinks::CreateService.call(
          project: project, channel_id: channel_id,
          channel_name: data['hourglass_channel_name'].to_s,
          integration: integration, current_user: actor_user(project.team),
          notify_outbound: false
        )
        track_link(result, 'project')
      end

      # Emitted here rather than inside the link services, which the web controllers share: the
      # controllers emit the same pair with via: "web", and only the caller knows which it is. The
      # existing `return if ...exists?` guards above are what stop a link mtasks created itself
      # from being counted twice when Hourglass echoes it back.
      def track_link(result, entity)
        return if result.error || result.link.nil?

        track_integration('hourglass-integration', 'link', result.link.id,
                          entity: entity, team: result.link.team)
      end

      def valid_project_channel?(project, channel_id)
        unless project
          logger.warn("link.created project_channel missing project=#{data['mtasks_project_id']}")
          return false
        end
        return logger.warn('link.created project_channel missing hourglass_channel_id') && false if channel_id.blank?

        true
      end

      def actor_user(team)
        team.users.find_by(id: data['created_by_user_id']) || team.users.first
      end
    end
  end
end
