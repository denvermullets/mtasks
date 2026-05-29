class AddWorkspaceAndOneTimeUseToApiTokens < ActiveRecord::Migration[8.1]
  def change
    add_reference :api_tokens, :workspace, foreign_key: true, null: true
    add_column :api_tokens, :one_time_use, :boolean, default: false, null: false
  end
end
