class CreateUserPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :user_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.string :view_mode, default: 'board'
      t.string :group_by, default: 'lane'
      t.string :order_by, default: 'manual'
      t.boolean :show_sub_issues, default: true
      t.boolean :show_empty_groups, default: false
      t.string :completed_filter
      t.json :visible_properties, default: ['id', 'priority', 'assignee', 'labels']

      t.timestamps
    end

    add_index :user_preferences, [:user_id, :team_id], unique: true
  end
end
