class CreateLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :labels do |t|
      t.string :name
      t.string :color
      t.references :team, null: false, foreign_key: true

      t.timestamps
    end
  end
end
