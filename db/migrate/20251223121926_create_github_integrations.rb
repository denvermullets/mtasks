class CreateGithubIntegrations < ActiveRecord::Migration[8.1]
  def change
    create_table :github_integrations do |t|
      t.references :team, null: false, foreign_key: true, index: { unique: true }
      t.string :github_repo_full_name, null: false
      t.string :encrypted_access_token
      t.string :encrypted_access_token_iv
      t.string :encrypted_refresh_token
      t.string :encrypted_refresh_token_iv
      t.string :installation_id
      t.boolean :active, default: true, null: false
      t.datetime :last_webhook_at
      t.datetime :token_expires_at

      t.timestamps
    end
  end
end
