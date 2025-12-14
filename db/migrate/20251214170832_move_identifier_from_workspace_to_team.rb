class MoveIdentifierFromWorkspaceToTeam < ActiveRecord::Migration[8.1]
  def change
    # Add identifier to teams
    add_column :teams, :identifier, :string
    add_index :teams, :identifier, unique: true

    # Remove identifier from workspaces
    remove_index :workspaces, :identifier
    remove_column :workspaces, :identifier, :string
  end
end
