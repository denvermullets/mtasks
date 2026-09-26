class CreateSavedViews < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_views do |t|
      t.references :user, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :query, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :saved_views, %i[user_id position]
  end
end
