module HourglassMessageUrlHelper
  def hourglass_message_url(message, integration:)
    return nil unless integration&.base_url.present?

    base = integration.base_url.to_s.chomp('/')
    server = integration.hourglass_server_id
    "#{base}/servers/#{server}/channels/#{message.hourglass_channel_id}?msg=#{message.hourglass_message_id}"
  end
end
