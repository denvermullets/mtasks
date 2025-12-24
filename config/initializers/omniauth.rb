Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github,
           ENV.fetch('GITHUB_CLIENT_ID', nil),
           ENV.fetch('GITHUB_CLIENT_SECRET', nil),
           scope: 'repo,write:repo_hook'
end

OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true
