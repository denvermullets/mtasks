module Discussion
  class PushCommentToChatService < Service
    Result = Struct.new(:success?, :channel_name, :error, keyword_init: true)

    def initialize(comment:, link: nil)
      @comment = comment
      @explicit_link = link
    end

    def call
      if @comment.pushed_to_hourglass_message_id.present?
        return Result.new(success?: true, channel_name: link&.hourglass_channel_name)
      end

      if link.nil? || link.broken?
        return Result.new(success?: false,
                          error: 'No active hourglass link for this comment.')
      end
      return Result.new(success?: false, error: 'Link is missing its integration.') if integration.nil?

      push!
    end

    private

    def push!
      body = ChatMessageFormatter.call(comment: @comment)
      response = post_message(body)
      message_id = response['id']&.to_s
      @comment.update!(
        pushed_to_hourglass_message_id: message_id,
        pushed_to_hourglass_at: Time.current
      )
      Result.new(success?: true, channel_name: link.hourglass_channel_name)
    rescue Hourglass::ApiClient::Error => e
      Rails.logger.warn("PushCommentToChatService failed: #{e.message}")
      Result.new(success?: false, error: e.message)
    end

    def post_message(body)
      key = "comment-#{@comment.id}-push"
      if link.link_type == 'issue_thread'
        api_client.post_thread_message(link.hourglass_thread_id, body: body, message_type: 'system',
                                                                 idempotency_key: key)
      else
        api_client.post_channel_message(link.hourglass_channel_id, body: body, message_type: 'system',
                                                                   idempotency_key: key)
      end
    end

    def link
      @link ||= @explicit_link || default_link
    end

    def default_link
      return nil unless @comment.project

      HourglassLink.for_project(@comment.project).active.first
    end

    def integration
      @integration ||= link&.hourglass_integration
    end

    def api_client
      @api_client ||= Hourglass::ApiClient.for_integration(integration)
    end
  end
end
