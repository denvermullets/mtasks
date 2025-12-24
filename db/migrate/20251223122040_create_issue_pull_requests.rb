class CreateIssuePullRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :issue_pull_requests do |t|
      t.references :issue, null: false, foreign_key: true
      t.references :pull_request, null: false, foreign_key: true
      t.boolean :comment_posted, default: false, null: false
      t.datetime :comment_posted_at

      t.timestamps
    end

    add_index :issue_pull_requests, [ :issue_id, :pull_request_id ], unique: true, name: "index_issue_pull_requests_on_issue_and_pr"
  end
end
