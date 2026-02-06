class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.references :issue, null: false, foreign_key: true
      t.bigint :version_id
      t.references :comment, foreign_key: true
      t.string :action, null: false
      t.text :message, null: false
      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications, [:user_id, :read_at]
    add_index :notifications, [:user_id, :created_at]
  end
end
