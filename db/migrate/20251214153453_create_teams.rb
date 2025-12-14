class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      t.string :name
      t.text :description
      t.references :workspace, null: false, foreign_key: true
      t.integer :issue_counter, default: 0

      t.timestamps
    end
  end
end
