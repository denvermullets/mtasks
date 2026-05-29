class CreateHourglassLinkReadStates < ActiveRecord::Migration[8.1]
  def change
    create_table :hourglass_link_read_states do |t|
      t.references :user, null: false, foreign_key: true
      t.references :hourglass_link, null: false, foreign_key: true
      t.datetime :last_read_at, null: false

      t.timestamps
    end

    add_index :hourglass_link_read_states, %i[user_id hourglass_link_id],
              unique: true, name: 'idx_hg_link_read_states_user_link_unique'
  end
end
