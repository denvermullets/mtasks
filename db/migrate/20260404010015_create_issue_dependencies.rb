class CreateIssueDependencies < ActiveRecord::Migration[8.1]
  def change
    create_table :issue_dependencies do |t|
      t.references :blocking_issue, null: false, foreign_key: { to_table: :issues }
      t.references :blocked_issue, null: false, foreign_key: { to_table: :issues }
      t.timestamps
    end

    add_index :issue_dependencies, [:blocking_issue_id, :blocked_issue_id], unique: true
  end
end
