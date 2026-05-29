class AddIdempotencyKeyToDecisions < ActiveRecord::Migration[8.1]
  def change
    add_column :decisions, :idempotency_key, :string
    add_index :decisions, :idempotency_key, unique: true, where: 'idempotency_key IS NOT NULL'
  end
end
