module HourglassIntegrations
  # Takes one team off an integration: its subscription goes inactive, the callback token stops
  # reaching it, and its links to this server are marked broken so the UI offers a relink. When the
  # last team leaves, the whole integration is disconnected and its token revoked.
  class UnsubscribeTeamService < Service
    def initialize(integration:, team:)
      @integration = integration
      @team = team
    end

    def call
      ActiveRecord::Base.transaction do
        sub = @integration.hourglass_channel_subscriptions.active.find_by(team: @team)
        next unless sub

        sub.update!(active: false)
        @integration.hourglass_links.where(team: @team).active.update_all(status: 'broken', updated_at: Time.current)

        if @integration.active_subscriptions.exists?
          @integration.sync_callback_token_scope!
        else
          DisconnectService.call(@integration)
        end
      end
      @integration
    end
  end
end
