class AddArchivedAtToTeams < ActiveRecord::Migration[8.1]
  def change
    add_column :teams, :archived_at, :datetime
  end
end
