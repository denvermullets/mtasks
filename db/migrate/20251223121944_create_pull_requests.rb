class CreatePullRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :pull_requests do |t|
      t.references :github_integration, null: false, foreign_key: true
      t.integer :pr_number, null: false
      t.string :title
      t.text :body
      t.string :html_url
      t.string :state
      t.string :author_login
      t.string :head_ref
      t.string :base_ref
      t.boolean :merged, default: false, null: false
      t.datetime :merged_at
      t.datetime :closed_at
      t.datetime :github_created_at
      t.datetime :github_updated_at

      t.timestamps
    end

    add_index :pull_requests, [ :github_integration_id, :pr_number ], unique: true
  end
end
