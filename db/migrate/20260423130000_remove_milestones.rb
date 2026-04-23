class RemoveMilestones < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :issues, :milestones if foreign_key_exists?(:issues, :milestones)
    remove_foreign_key :projects, :milestones if foreign_key_exists?(:projects, :milestones)

    remove_index :issues, :milestone_id if index_exists?(:issues, :milestone_id)
    remove_index :projects, :milestone_id if index_exists?(:projects, :milestone_id)

    remove_column :issues, :milestone_id if column_exists?(:issues, :milestone_id)
    remove_column :projects, :milestone_id if column_exists?(:projects, :milestone_id)

    drop_table :milestones if table_exists?(:milestones)

    # Clean up user_preferences that used the milestone grouping/property.
    execute <<~SQL.squish
      UPDATE user_preferences
      SET group_by = 'status'
      WHERE group_by = 'milestone'
    SQL

    execute <<~SQL.squish
      UPDATE user_preferences
      SET visible_properties = (
        SELECT COALESCE(json_agg(elem), '[]'::json)
        FROM json_array_elements_text(visible_properties) AS elem
        WHERE elem <> 'milestone'
      )
      WHERE visible_properties::text LIKE '%milestone%'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Milestones have been removed; recreate from source control if needed.'
  end
end
