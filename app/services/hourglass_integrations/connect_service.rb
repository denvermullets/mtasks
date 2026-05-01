module HourglassIntegrations
  class ConnectService < Service
    Result = Struct.new(:integration, :channel_count, keyword_init: true)

    def initialize(workspace:, current_user:, base_url:, api_token:)
      @workspace = workspace
      @current_user = current_user
      @base_url = base_url
      @api_token = api_token
    end

    def call
      client = Hourglass::ApiClient.new(base_url: @base_url, api_token: @api_token)
      client.verify_token

      webhook_secret = SecureRandom.hex(32)
      callback_token = mint_callback_token

      begin
        handshake = perform_handshake(client, webhook_secret, callback_token)
        persist_and_discover(client, handshake, webhook_secret, callback_token)
      rescue StandardError
        callback_token.revoke! unless callback_token.revoked?
        raise
      end
    end

    private

    def mint_callback_token
      ApiToken.generate_for(
        @current_user,
        name: "Hourglass connection (workspace #{@workspace.id})",
        scopes: %w[read write]
      )
    end

    def perform_handshake(client, webhook_secret, callback_token)
      response = client.handshake!(
        webhook_url: webhook_url_for(@workspace),
        webhook_secret: webhook_secret,
        callback_token: callback_token.raw_token
      )
      raise Hourglass::ApiClient::Error, 'Hourglass handshake missing server_id' if response['server_id'].to_s.blank?

      response
    end

    def persist_and_discover(client, handshake, webhook_secret, callback_token)
      server_id = handshake['server_id'].to_s
      server_name = handshake['server_name'].to_s
      ActiveRecord::Base.transaction do
        integration = persist_integration(server_id:, server_name:, webhook_secret:, callback_token:)
        channels = client.discover_channels!
        fan_out_subscriptions(integration:, server_id:, server_name:)
        Result.new(integration: integration, channel_count: channels.size)
      end
    end

    def persist_integration(server_id:, server_name:, webhook_secret:, callback_token:)
      integration = @workspace.hourglass_integrations.find_or_initialize_by(hourglass_server_id: server_id)
      integration.assign_attributes(
        hourglass_server_name: server_name,
        base_url: @base_url,
        api_token: @api_token,
        webhook_secret: webhook_secret,
        connected_by_user: @current_user,
        callback_api_token: callback_token,
        active: true,
        connected_at: Time.current,
        last_verified_at: Time.current
      )
      integration.save!
      integration
    end

    def fan_out_subscriptions(integration:, server_id:, server_name:)
      @workspace.teams.find_each do |team|
        sub = HourglassChannelSubscription.find_or_initialize_by(
          hourglass_integration: integration,
          team: team
        )
        sub.assign_attributes(
          hourglass_server_id: server_id,
          hourglass_server_name: server_name,
          active: true
        )
        sub.save!
      end
    end

    def webhook_url_for(workspace)
      host = ENV.fetch('APP_HOST', 'localhost:3000')
      scheme = Rails.env.production? ? 'https' : 'http'
      "#{scheme}://#{host}/webhooks/hourglass/#{workspace.id}"
    end
  end
end
