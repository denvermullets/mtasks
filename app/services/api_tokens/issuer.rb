module ApiTokens
  class Issuer < Service
    DEFAULT_SCOPES = ApiToken::AVAILABLE_SCOPES

    def initialize(user:, workspace:, name:, scopes: DEFAULT_SCOPES, one_time_use: false)
      @user = user
      @workspace = workspace
      @name = name
      @scopes = scopes
      @one_time_use = one_time_use
    end

    def call
      raw = SecureRandom.base58(36)
      token = @user.api_tokens.create!(
        token_digest: Digest::SHA256.hexdigest(raw),
        name: @name,
        workspace: @workspace,
        one_time_use: @one_time_use,
        scopes: Array(@scopes).map(&:to_s)
      )
      token.raw_token = raw
      token
    end
  end
end
