class CreatePendingGithubSetups < ActiveRecord::Migration[8.1]
  def change
    create_table :pending_github_setups do |t|
      t.references :team, null: false, foreign_key: true
      t.string :installation_id
      t.datetime :expires_at

      t.timestamps
    end

    # Index for looking up pending setups when webhooks arrive
    add_index :pending_github_setups, :installation_id
    # Index for cleaning up expired records
    add_index :pending_github_setups, :expires_at
  end
end
