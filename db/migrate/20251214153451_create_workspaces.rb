class CreateWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :workspaces do |t|
      t.string :name
      t.string :identifier
      t.references :owner, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
    add_index :workspaces, :identifier, unique: true
  end
end
