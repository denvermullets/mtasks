class CreateGithubInstallations < ActiveRecord::Migration[8.1]
  def change
    create_table :github_installations do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :installation_id, null: false
      t.string :github_account_login
      t.string :github_account_type
      t.boolean :active, default: true, null: false
      t.datetime :last_webhook_at

      t.timestamps
    end

    add_index :github_installations, :installation_id, unique: true
  end
end
