class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name
      t.text :description
      t.references :team, null: false, foreign_key: true
      t.references :milestone, foreign_key: true

      t.timestamps
    end
  end
end
