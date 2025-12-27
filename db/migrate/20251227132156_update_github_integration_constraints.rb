class UpdateGithubIntegrationConstraints < ActiveRecord::Migration[8.1]
  def change
    # Remove the unique index on team_id (this removes the uniqueness constraint)
    # The existing index is: index_github_integrations_on_team_id, unique: true
    remove_index :github_integrations, name: 'index_github_integrations_on_team_id'

    # Add back a NON-unique index on team_id for query performance
    add_index :github_integrations, :team_id

    # Add composite unique index: one integration per team+installation+repo
    # This allows a team to have multiple integrations (different repos)
    add_index :github_integrations,
              [:team_id, :installation_id, :github_repo_full_name],
              unique: true,
              name: 'index_github_integrations_on_team_installation_repo'
  end
end
