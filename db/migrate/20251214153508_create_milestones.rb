class CreateMilestones < ActiveRecord::Migration[8.1]
  def change
    create_table :milestones do |t|
      t.string :name
      t.text :description
      t.date :start_date
      t.date :due_date
      t.references :team, null: false, foreign_key: true

      t.timestamps
    end
  end
end
