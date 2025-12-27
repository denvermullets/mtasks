class ChangePendingGithubSetupsToWorkspaceScoped < ActiveRecord::Migration[8.1]
  def change
    # Remove team_id column and add workspace_id column
    remove_reference :pending_github_setups, :team, foreign_key: true
    add_reference :pending_github_setups, :workspace, null: false, foreign_key: true
  end
end
