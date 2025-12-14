class CreateIssueLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :issue_labels do |t|
      t.references :issue, null: false, foreign_key: true
      t.references :label, null: false, foreign_key: true

      t.timestamps
    end
  end
end
