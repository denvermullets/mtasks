require 'test_helper'

module ApiTokens
  class IssuerTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: 'Issuer User', email: "issuer_#{SecureRandom.hex(4)}@example.com",
                           password: 'password')
      @workspace = Workspace.create!(name: 'Issuer WS', owner: @user)
    end

    test 'workspace_token persists workspace and one_time_use, returns raw_token' do
      token = Issuer.workspace_token(user: @user, workspace: @workspace, name: 'b', one_time_use: true)

      assert token.persisted?
      assert_equal @workspace, token.workspace
      assert token.one_time_use?
      assert_predicate token.raw_token, :present?
      assert_equal Digest::SHA256.hexdigest(token.raw_token), token.token_digest
    end

    test 'workspace_token defaults to one_time_use false and full scopes' do
      token = Issuer.workspace_token(user: @user, workspace: @workspace, name: 'cb')

      assert_not token.one_time_use?
      assert_equal %w[read write], token.scopes
    end

    test 'workspace_token coerces scopes to strings' do
      token = Issuer.workspace_token(user: @user, workspace: @workspace, name: 'r', scopes: [:read])
      assert_equal %w[read], token.scopes
    end
  end
end
