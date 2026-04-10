class CreateIssueReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :issue_references do |t|
      t.references :source_issue, null: false, foreign_key: { to_table: :issues }
      t.references :referenced_issue, null: false, foreign_key: { to_table: :issues }
      t.references :user, null: false, foreign_key: true
      t.string :source_type, null: false

      t.timestamps
    end

    add_index :issue_references, %i[source_issue_id referenced_issue_id source_type],
              unique: true, name: 'idx_issue_refs_unique'
  end
end
