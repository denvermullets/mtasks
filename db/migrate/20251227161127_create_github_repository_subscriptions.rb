class CreateGithubRepositorySubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :github_repository_subscriptions do |t|
      t.references :team, null: false, foreign_key: true
      t.references :github_installation, null: false, foreign_key: true
      t.string :github_repo_full_name, null: false
      t.boolean :active, default: true, null: false
      t.datetime :last_webhook_at

      t.timestamps
    end

    add_index :github_repository_subscriptions,
              [:team_id, :github_installation_id, :github_repo_full_name],
              unique: true,
              name: 'index_gh_repo_subs_on_team_installation_repo'

    add_index :github_repository_subscriptions,
              [:github_installation_id, :github_repo_full_name, :active],
              name: 'index_gh_repo_subs_for_webhook_lookup'
  end
end
