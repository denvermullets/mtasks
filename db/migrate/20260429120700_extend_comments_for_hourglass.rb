class ExtendCommentsForHourglass < ActiveRecord::Migration[8.1]
  def change
    add_reference :comments, :project, foreign_key: true, null: true, index: true
    add_column :comments, :pushed_to_hourglass_message_id, :string
    add_column :comments, :pushed_to_hourglass_at, :datetime
    add_index :comments, :pushed_to_hourglass_message_id

    change_column_null :comments, :issue_id, true

    add_check_constraint :comments,
                         '(issue_id IS NULL) <> (project_id IS NULL)',
                         name: 'comments_owner_xor'
  end
end
