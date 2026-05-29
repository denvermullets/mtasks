class CreateDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :decisions do |t|
      t.references :team, null: false, foreign_key: true
      t.references :project, foreign_key: true
      t.references :issue, foreign_key: true
      t.string :hourglass_message_id, null: false
      t.references :pinned_by_user, foreign_key: { to_table: :users }
      t.datetime :pinned_at, null: false
      t.text :body_snapshot, null: false
      t.datetime :unpinned_at

      t.timestamps
    end

    add_index :decisions, :hourglass_message_id, unique: true
  end
end
