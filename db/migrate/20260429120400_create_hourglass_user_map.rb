class CreateHourglassUserMap < ActiveRecord::Migration[8.1]
  def change
    create_table :hourglass_user_map do |t|
      t.references :mtasks_user, null: false, foreign_key: { to_table: :users }
      t.string :hourglass_user_id, null: false
      t.string :email, null: false
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :hourglass_user_map, :email, unique: true
    add_index :hourglass_user_map, :hourglass_user_id, unique: true
  end
end
