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
    assert_not token.team_scoped?
    assert_empty token.scoped_teams
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
    token = ApiToken.generate_for(@user, name: 'Scoped', teams: [@team], scopes: %w[read])

    assert_equal [@team], token.scoped_teams.to_a
    assert_equal %w[read], token.scopes
    assert token.team_scoped?
    assert token.can_read?
    assert_not token.can_write?
  end

  test 'unscoped token allows any team' do
    token = ApiToken.generate_for(@user)
    other = @workspace.teams.create!(name: 'Other', identifier: 'OTHR')

    assert token.allows_team?(@team)
    assert token.allows_team?(other)
  end

  test 'team-scoped token allows only teams in its set' do
    b = @workspace.teams.create!(name: 'Bravo', identifier: 'BRV')
    c = @workspace.teams.create!(name: 'Charlie', identifier: 'CHR')
    token = ApiToken.generate_for(@user, teams: [@team, b])

    assert token.allows_team?(@team)
    assert token.allows_team?(b)
    assert_not token.allows_team?(c)
    assert_equal [@team.id, b.id].sort, token.filter_teams(Team.all).pluck(:id).sort
  end

  test 'scope is mutable without changing the credential' do
    b = @workspace.teams.create!(name: 'Bravo', identifier: 'BRV')
    token = ApiToken.generate_for(@user, teams: [@team])
    raw = token.raw_token
    digest = token.token_digest

    token.add_team!(b)
    assert token.allows_team?(b)

    token.remove_team!(@team)
    assert_not token.allows_team?(@team)
    assert_equal [b.id], token.scoped_team_ids

    assert_equal digest, token.reload.token_digest
    assert_equal token, ApiToken.authenticate(raw)
  end

  test 'removing the last team leaves the token reaching nothing, not everything' do
    token = ApiToken.generate_for(@user, teams: [@team])
    token.remove_team!(@team)

    assert token.team_scoped?
    assert_not token.allows_team?(@team)
    assert_empty token.filter_teams(@user.teams)
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
