module HourglassIntegrations
  class DisconnectService < Service
    def initialize(integration)
      @integration = integration
    end

    def call
      ActiveRecord::Base.transaction do
        @integration.update!(active: false)
        @integration.callback_api_token&.revoke! unless @integration.callback_api_token&.revoked?
      end
      @integration
    end
  end
end
