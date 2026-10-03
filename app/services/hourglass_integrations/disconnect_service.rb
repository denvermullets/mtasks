module HourglassIntegrations
  class DisconnectService < Service
    def initialize(integration)
      @integration = integration
    end

    # Deactivates the subscriptions too, so a later reconnect only opts in the teams it names
    # instead of reviving everyone who was on the server before.
    def call
      ActiveRecord::Base.transaction do
        @integration.update!(active: false)
        @integration.hourglass_channel_subscriptions.active.update_all(active: false, updated_at: Time.current)
        @integration.hourglass_links.active.update_all(status: 'broken', updated_at: Time.current)
        @integration.live_callback_token&.revoke!
      end
      @integration
    end
  end
end
