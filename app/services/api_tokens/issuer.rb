module ApiTokens
  class Issuer < Service
    DEFAULT_SCOPES = ApiToken::AVAILABLE_SCOPES

    # workspace: only for one-time bootstrap tokens, naming where the handshake connects. teams: the
    # team set the token may reach (nil = unscoped, see ApiToken.generate_for).
    def initialize(user:, name:, workspace: nil, teams: nil, scopes: DEFAULT_SCOPES, one_time_use: false)
      @user = user
      @workspace = workspace
      @teams = teams
      @name = name
      @scopes = scopes
      @one_time_use = one_time_use
    end

    def call
      raw = SecureRandom.base58(36)
      token = ApiToken.transaction do
        @user.api_tokens.create!(
          token_digest: Digest::SHA256.hexdigest(raw),
          name: @name,
          workspace: @workspace,
          one_time_use: @one_time_use,
          scopes: Array(@scopes).map(&:to_s)
        ).tap { |t| t.scope_to_teams!(@teams) unless @teams.nil? }
      end
      token.raw_token = raw
      token
    end
  end
end
