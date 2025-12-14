class CreateLanes < ActiveRecord::Migration[8.1]
  def change
    create_table :lanes do |t|
      t.string :name
      t.integer :position
      t.string :color
      t.references :team, null: false, foreign_key: true

      t.timestamps
    end
  end
end
