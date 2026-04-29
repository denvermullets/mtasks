class CreateHourglassIntegrations < ActiveRecord::Migration[8.1]
  def change
    create_table :hourglass_integrations do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :hourglass_server_id, null: false
      t.string :hourglass_server_name
      t.string :base_url, null: false
      t.text :api_token
      t.text :webhook_secret
      t.boolean :active, default: true, null: false
      t.references :connected_by_user, foreign_key: { to_table: :users }
      t.datetime :connected_at
      t.datetime :last_webhook_at
      t.datetime :last_verified_at

      t.timestamps
    end

    add_index :hourglass_integrations, %i[workspace_id hourglass_server_id], unique: true
  end
end
