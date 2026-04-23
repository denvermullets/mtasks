class AddTeamAndScopesToApiTokens < ActiveRecord::Migration[8.1]
  def change
    add_reference :api_tokens, :team, null: true, foreign_key: true
    add_column :api_tokens, :scopes, :string, array: true, null: false, default: %w[read write]
  end
end
