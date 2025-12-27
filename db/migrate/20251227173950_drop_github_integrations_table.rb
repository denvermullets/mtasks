class DropGithubIntegrationsTable < ActiveRecord::Migration[8.1]
  def change
    drop_table :github_integrations
  end
end
