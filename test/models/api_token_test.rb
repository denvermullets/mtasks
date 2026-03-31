require 'test_helper'

class ApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Token User', email: 'token@example.com', password: 'password')
  end

  test 'generate_for creates a token and returns raw value' do
    token = ApiToken.generate_for(@user)

    assert token.persisted?
    assert token.raw_token.present?
    assert_equal 36, token.raw_token.length
    assert_equal @user, token.user
    assert_nil token.revoked_at
  end

  test 'generate_for revokes existing active tokens' do
    first_token = ApiToken.generate_for(@user)
    second_token = ApiToken.generate_for(@user)

    first_token.reload
    assert first_token.revoked?
    assert_not second_token.revoked?
  end

  test 'authenticate finds token by raw value' do
    token = ApiToken.generate_for(@user)
    found = ApiToken.authenticate(token.raw_token)

    assert_equal token.id, found.id
  end

  test 'authenticate returns nil for invalid token' do
    assert_nil ApiToken.authenticate('invalid_token')
  end

  test 'authenticate returns nil for blank token' do
    assert_nil ApiToken.authenticate(nil)
    assert_nil ApiToken.authenticate('')
  end

  test 'authenticate returns nil for revoked token' do
    token = ApiToken.generate_for(@user)
    token.revoke!

    assert_nil ApiToken.authenticate(token.raw_token)
  end

  test 'revoke sets revoked_at' do
    token = ApiToken.generate_for(@user)
    assert_nil token.revoked_at

    token.revoke!
    assert_not_nil token.revoked_at
    assert token.revoked?
  end

  test 'token_digest is a SHA256 hex digest' do
    token = ApiToken.generate_for(@user)
    expected_digest = Digest::SHA256.hexdigest(token.raw_token)

    assert_equal expected_digest, token.token_digest
  end
end
