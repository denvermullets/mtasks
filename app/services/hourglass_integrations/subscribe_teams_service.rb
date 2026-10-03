module HourglassIntegrations
  # Opts teams into an integration and widens its callback token to match, in one transaction, so the
  # token's team set never drifts from the active subscriptions.
  class SubscribeTeamsService < Service
    def initialize(integration:, teams:)
      @integration = integration
      @teams = Array(teams)
    end

    def call
      ActiveRecord::Base.transaction do
        @teams.each { |team| activate(team) }
        @integration.sync_callback_token_scope!
      end
      @integration
    end

    private

    def activate(team)
      sub = @integration.hourglass_channel_subscriptions.find_or_initialize_by(team: team)
      sub.assign_attributes(
        hourglass_server_id: @integration.hourglass_server_id,
        hourglass_server_name: @integration.hourglass_server_name,
        active: true
      )
      sub.save!
    end
  end
end
