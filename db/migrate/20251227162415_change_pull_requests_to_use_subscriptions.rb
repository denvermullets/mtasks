class ChangePullRequestsToUseSubscriptions < ActiveRecord::Migration[8.1]
  def change
    # Remove old foreign key and add new one
    remove_reference :pull_requests, :github_integration, foreign_key: true
    add_reference :pull_requests, :github_repository_subscription, null: false, foreign_key: true
  end
end
