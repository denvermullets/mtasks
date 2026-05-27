class AddOwnerToTeams < ActiveRecord::Migration[8.1]
  def up
    add_reference :teams, :owner, foreign_key: { to_table: :users }, null: true

    execute(<<~SQL)
      UPDATE teams t
      SET owner_id = w.owner_id
      FROM workspaces w
      WHERE w.id = t.workspace_id AND t.owner_id IS NULL
    SQL

    change_column_null :teams, :owner_id, false
  end

  def down
    remove_reference :teams, :owner, foreign_key: { to_table: :users }
  end
end
