module HourglassIntegrations
  # Connects the given teams to the Hourglass server behind api_token. One integration per server per
  # workspace: if the server is already connected, its integration is reused and the teams are added
  # to it; the stored credentials are only replaced when replace_credentials is set.
  class ConnectService < Service
    Result = Struct.new(:integration, :channel_count, :new_callback_token, :reused, keyword_init: true)

    def initialize(workspace:, current_user:, base_url:, api_token:, teams:, replace_credentials: false)
      @workspace = workspace
      @current_user = current_user
      @base_url = base_url
      @api_token = api_token
      @teams = Array(teams)
      @replace_credentials = replace_credentials
    end

    def call
      validate_teams!
      client = Hourglass::ApiClient.new(base_url: @base_url, api_token: @api_token)
      identity = derive_identity(client.verify_token)
      existing = @workspace.hourglass_integrations.find_by(hourglass_server_id: identity[:server_id])
      reuse = reusable?(existing)

      callback_token = reuse ? nil : mint_callback_token(identity[:server_name])
      begin
        persist_and_discover(client:, identity:, existing:, reuse:, callback_token:)
      rescue StandardError
        callback_token&.revoke! unless callback_token&.revoked?
        raise
      end
    end

    private

    def validate_teams!
      raise ArgumentError, 'Pick at least one team' if @teams.empty?
      return if @teams.all? { |t| t.workspace_id == @workspace.id }

      raise ArgumentError, 'Teams must belong to this workspace'
    end

    # A live connection keeps its callback token (Hourglass already holds it); a disconnected one,
    # or one whose token was revoked, starts over.
    def reusable?(existing)
      existing.present? && existing.active? && existing.live_callback_token.present?
    end

    # Starts with no teams; SubscribeTeamsService widens it to the subscriptions in the same
    # transaction that creates them.
    def mint_callback_token(server_name)
      ApiToken.generate_for(
        @current_user,
        name: "Hourglass connection (#{server_name})",
        teams: [],
        scopes: %w[read write]
      )
    end

    def derive_identity(me_response)
      server_id, server_name = derive_server_identity(me_response)
      integration_id, remote_secret = derive_integration_identity(me_response)
      { server_id:, server_name:, integration_id:, remote_secret: }
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

    def persist_and_discover(client:, identity:, existing:, reuse:, callback_token:)
      client.server_id = identity[:server_id]
      ActiveRecord::Base.transaction do
        integration = existing || @workspace.hourglass_integrations.new(hourglass_server_id: identity[:server_id])
        if reuse
          refresh_credentials(integration, identity) if @replace_credentials
        else
          assign_fresh_connection(integration, identity, callback_token)
        end
        integration.save!

        channels = best_effort_discover_channels(client)
        SubscribeTeamsService.call(integration: integration, teams: @teams)
        Result.new(integration: integration, channel_count: channels.size,
                   new_callback_token: callback_token&.raw_token, reused: reuse)
      end
    end

    def best_effort_discover_channels(client)
      client.discover_channels!
    rescue Hourglass::ApiClient::NotFound, Hourglass::ApiClient::Unauthorized => e
      Rails.logger.warn("Hourglass channel discovery skipped: #{e.message}")
      []
    end

    # New or previously disconnected integration: nothing live to protect, so take the new
    # credentials and token outright.
    def assign_fresh_connection(integration, identity, callback_token)
      refresh_credentials(integration, identity)
      integration.assign_attributes(
        webhook_secret: identity[:remote_secret].presence || SecureRandom.hex(32),
        callback_api_token: callback_token,
        active: true,
        connected_at: Time.current
      )
    end

    def refresh_credentials(integration, identity)
      integration.assign_attributes(
        hourglass_server_name: identity[:server_name],
        hourglass_integration_id: identity[:integration_id] || integration.hourglass_integration_id,
        base_url: @base_url,
        api_token: @api_token,
        connected_by_user: @current_user,
        last_verified_at: Time.current
      )
      integration.webhook_secret = identity[:remote_secret] if identity[:remote_secret].present?
    end
  end
end
