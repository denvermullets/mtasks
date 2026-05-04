module HourglassWebhookProcessor
  module Link
    class RemovedHandler < BaseHandler
      def call
        case link_type
        when 'issue_thread'    then handle_issue_thread
        when 'project_channel' then handle_project_channel
        else
          logger.warn("link.removed unknown link_type=#{link_type.inspect} (delivery=#{delivery.delivery_id})")
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
        thread_id = data['hourglass_thread_id'].to_s
        link = HourglassLink.issue_thread.where(hourglass_thread_id: thread_id).first
        return logger.info("link.removed issue_thread idempotent (thread=#{thread_id})") unless link

        HourglassLinks::DestroyService.call(link: link, notify_outbound: false)
      end

      def handle_project_channel
        channel_id = data['hourglass_channel_id'].to_s
        link = HourglassLink.project_channel.where(hourglass_channel_id: channel_id).first
        return logger.info("link.removed project_channel idempotent (channel=#{channel_id})") unless link

        HourglassLinks::DestroyService.call(link: link, notify_outbound: false)
      end
    end
  end
end
