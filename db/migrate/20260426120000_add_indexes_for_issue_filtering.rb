class AddIndexesForIssueFiltering < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :issues, :team_id,
              where: 'archived_at IS NULL',
              name: 'index_issues_on_team_id_not_archived',
              algorithm: :concurrently
    add_index :issues, :team_id,
              where: 'completed_at IS NULL AND canceled_at IS NULL',
              name: 'index_issues_on_team_id_open',
              algorithm: :concurrently
    add_index :issue_labels, %i[label_id issue_id],
              name: 'index_issue_labels_on_label_id_and_issue_id',
              algorithm: :concurrently
  end
end
