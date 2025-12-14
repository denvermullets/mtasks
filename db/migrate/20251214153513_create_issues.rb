class CreateIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :issues do |t|
      t.string :title
      t.text :description
      t.integer :team_number
      t.references :lane, null: false, foreign_key: true
      t.integer :estimate
      t.integer :priority, default: 4
      t.date :due_date
      t.references :parent_issue, foreign_key: { to_table: :issues }
      t.references :project, foreign_key: true
      t.references :milestone, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.references :creator, foreign_key: { to_table: :users }
      t.references :assignee, foreign_key: { to_table: :users }
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :canceled_at
      t.datetime :archived_at

      t.timestamps
    end
    add_index :issues, [:team_id, :team_number], unique: true
  end
end
