module ApiTestHelper
  def api_headers_for(user)
    token = ApiToken.generate_for(user)
    { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ApiTestHelper
end
