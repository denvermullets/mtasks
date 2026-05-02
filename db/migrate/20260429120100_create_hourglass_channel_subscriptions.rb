class CreateHourglassChannelSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :hourglass_channel_subscriptions do |t|
      t.references :hourglass_integration, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.string :hourglass_server_id, null: false
      t.string :hourglass_server_name
      t.boolean :active, default: true, null: false
      t.datetime :last_webhook_at

      t.timestamps
    end

    add_index :hourglass_channel_subscriptions,
              %i[team_id hourglass_integration_id],
              unique: true,
              name: 'idx_hg_subs_team_integration_unique'
  end
end
