require 'test_helper'

class ApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Token User', email: 'token@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Token WS', owner: @user)
    @team = @workspace.teams.create!(name: 'Token Team', identifier: 'TKN')
    @team.team_memberships.create!(user: @user)
  end

  test 'generate_for creates a token and returns raw value' do
    token = ApiToken.generate_for(@user, name: 'Test')

    assert token.persisted?
    assert token.raw_token.present?
    assert_equal 36, token.raw_token.length
    assert_equal @user, token.user
    assert_equal 'Test', token.name
    assert_nil token.revoked_at
    assert_equal %w[read write], token.scopes
    assert_nil token.team_id
  end

  test 'generate_for does not revoke existing tokens (multi-token support)' do
    first = ApiToken.generate_for(@user, name: 'First')
    second = ApiToken.generate_for(@user, name: 'Second')

    first.reload
    assert_not first.revoked?
    assert_not second.revoked?
    assert_equal 2, @user.api_tokens.active.count
  end

  test 'generate_for accepts team and scopes' do
    token = ApiToken.generate_for(@user, name: 'Scoped', team: @team, scopes: %w[read])

    assert_equal @team, token.team
    assert_equal %w[read], token.scopes
    assert token.scoped_to_team?
    assert token.can_read?
    assert_not token.can_write?
  end

  test 'scopes must be a subset of available scopes' do
    token = ApiToken.new(user: @user, token_digest: 'x', scopes: %w[admin])
    assert_not token.valid?
    assert_includes token.errors[:scopes].join, 'subset'
  end

  test 'scopes must be present' do
    token = ApiToken.new(user: @user, token_digest: 'x', scopes: [])
    assert_not token.valid?
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

  test 'workspace and one_time_use default to nil/false' do
    token = ApiToken.generate_for(@user)
    assert_nil token.workspace_id
    assert_not token.one_time_use?
  end
end
