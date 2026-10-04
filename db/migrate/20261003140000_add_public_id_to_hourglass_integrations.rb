class AddPublicIdToHourglassIntegrations < ActiveRecord::Migration[8.1]
  # Inbound webhooks are addressed per integration. A random uuid keeps integration ids out of the
  # URL so they can't be enumerated; the DB default also backfills existing rows.
  def change
    add_column :hourglass_integrations, :public_id, :uuid, null: false, default: -> { 'gen_random_uuid()' }
    add_index :hourglass_integrations, :public_id, unique: true
  end
end
