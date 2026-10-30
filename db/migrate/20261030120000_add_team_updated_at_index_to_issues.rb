class AddTeamUpdatedAtIndexToIssues < ActiveRecord::Migration[8.1]
  def change
    add_index :issues, %i[team_id updated_at]
  end
end
