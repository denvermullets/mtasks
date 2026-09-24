class AddRecurringIssueToIssues < ActiveRecord::Migration[8.1]
  def change
    add_reference :issues, :recurring_issue, foreign_key: { on_delete: :nullify }
  end
end
