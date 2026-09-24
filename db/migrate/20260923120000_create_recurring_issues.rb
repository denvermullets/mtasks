class CreateRecurringIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_issues do |t|
      t.references :team, null: false, foreign_key: true
      t.references :creator, foreign_key: { to_table: :users }
      t.references :assignee, foreign_key: { to_table: :users }
      t.references :project, foreign_key: { on_delete: :nullify }
      # Nullable: a spawn falls back to the team's first lane, so deleting a lane never strands a schedule.
      t.references :lane, foreign_key: { on_delete: :nullify }
      t.string :title, null: false
      t.text :description
      t.integer :priority, null: false, default: 4
      t.bigint :label_ids, array: true, null: false, default: []
      t.integer :frequency, null: false, default: 1
      t.integer :interval, null: false, default: 1
      t.integer :weekday
      t.integer :day_of_month
      # next_run_on is a calendar date in this zone; the sweep files it once local midnight has passed.
      t.string :time_zone, null: false, default: 'UTC'
      t.date :next_run_on, null: false, index: { where: 'active' }
      t.datetime :last_run_at
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
