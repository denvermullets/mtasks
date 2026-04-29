class CreateWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_deliveries do |t|
      t.string :source, null: false
      t.string :delivery_id, null: false
      t.string :event_type, null: false
      t.datetime :received_at, null: false
      t.datetime :processed_at
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :webhook_deliveries, %i[source delivery_id], unique: true
    add_index :webhook_deliveries, :received_at
  end
end
