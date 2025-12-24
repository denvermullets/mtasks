# GitHub App Configuration
module GithubApp
  class << self
    def app_id
      ENV.fetch('GITHUB_APP_ID')
    end

    def private_key
      # Decode base64-encoded private key
      encoded_key = ENV.fetch('GITHUB_APP_PRIVATE_KEY')
      decoded_key = Base64.decode64(encoded_key)
      OpenSSL::PKey::RSA.new(decoded_key)
    end

    def webhook_secret
      ENV.fetch('GITHUB_WEBHOOK_SECRET')
    end

    # Generate JWT for authenticating as the GitHub App
    def generate_jwt
      payload = {
        iat: Time.now.to_i - 60,
        exp: Time.now.to_i + (10 * 60),
        iss: app_id
      }

      JWT.encode(payload, private_key, 'RS256')
    end

    # Get an installation access token for a specific installation
    def installation_token(installation_id)
      client = Octokit::Client.new(bearer_token: generate_jwt)
      response = client.create_app_installation_access_token(installation_id)
      response[:token]
    end
  end
end
