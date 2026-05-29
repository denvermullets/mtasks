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
      me = client.verify_token

      callback_token = mint_callback_token
      server_id, server_name = derive_server_identity(me)
      integration_id, remote_secret = derive_integration_identity(me)
      webhook_secret = remote_secret.presence || SecureRandom.hex(32)

      begin
        persist_and_discover(
          client: client,
          identity: { server_id: server_id, server_name: server_name, integration_id: integration_id },
          credentials: { webhook_secret: webhook_secret, callback_token: callback_token }
        )
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

    def derive_integration_identity(me_response)
      integration = me_response.is_a?(Hash) ? me_response['integration'] : nil
      return [nil, nil] unless integration.is_a?(Hash)

      [integration['id'], integration['webhook_secret']]
    end

    def derive_server_identity(me_response)
      server = me_response.is_a?(Hash) ? me_response['server'] : nil
      unless server.is_a?(Hash) && server['id'].present?
        raise Hourglass::ApiClient::Error, 'Hourglass /me did not return a server'
      end

      server_id = server['id'].to_s
      server_name = server['name'].present? ? server['name'].to_s : server_id
      [server_id, server_name]
    end

    def persist_and_discover(client:, identity:, credentials:)
      client.server_id = identity[:server_id]
      ActiveRecord::Base.transaction do
        integration = persist_integration(
          server_id: identity[:server_id], server_name: identity[:server_name],
          webhook_secret: credentials[:webhook_secret], callback_token: credentials[:callback_token],
          hourglass_integration_id: identity[:integration_id]
        )
        channels = best_effort_discover_channels(client)
        fan_out_subscriptions(integration:, server_id: identity[:server_id], server_name: identity[:server_name])
        Result.new(integration: integration, channel_count: channels.size)
      end
    end

    def best_effort_discover_channels(client)
      client.discover_channels!
    rescue Hourglass::ApiClient::NotFound, Hourglass::ApiClient::Unauthorized => e
      Rails.logger.warn("Hourglass channel discovery skipped: #{e.message}")
      []
    end

    def persist_integration(server_id:, server_name:, webhook_secret:, callback_token:, hourglass_integration_id:)
      integration = @workspace.hourglass_integrations.find_or_initialize_by(hourglass_server_id: server_id)
      integration.assign_attributes(
        hourglass_server_name: server_name,
        hourglass_integration_id: hourglass_integration_id,
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
  end
end
