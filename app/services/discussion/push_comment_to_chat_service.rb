module Discussion
  class PushCommentToChatService < Service
    Result = Struct.new(:success?, :channel_name, :error, keyword_init: true)

    def initialize(comment:)
      @comment = comment
    end

    def call
      if @comment.pushed_to_hourglass_message_id.present?
        return Result.new(success?: true,
                          channel_name: link&.hourglass_channel_name)
      end

      if link.nil? || link.broken?
        return Result.new(success?: false,
                          error: 'No active hourglass channel link for this project.')
      end
      return Result.new(success?: false, error: 'Channel link is missing its integration.') if integration.nil?

      push!
    end

    private

    def push!
      body = ChatMessageFormatter.call(comment: @comment)
      response = api_client.post_channel_message(
        link.hourglass_channel_id,
        body: body,
        message_type: 'system',
        idempotency_key: "comment-#{@comment.id}-push"
      )
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

    def link
      @link ||= HourglassLink.for_project(@comment.project).active.first
    end

    def integration
      @integration ||= link&.hourglass_integration
    end

    def api_client
      @api_client ||= Hourglass::ApiClient.for_integration(integration)
    end
  end
end
