class AddRoleToTeamMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :team_memberships, :role, :integer, default: 0, null: false
    add_index :team_memberships, %i[team_id role]
  end
end
