class AddCategoryToLanes < ActiveRecord::Migration[8.1]
  def up
    add_column :lanes, :category, :string, null: false, default: 'started'

    # Mirrors the old name-based rules: Done completed, Cancelled/Canceled canceled.
    execute <<~SQL.squish
      UPDATE lanes SET category = CASE LOWER(TRIM(name))
        WHEN 'backlog' THEN 'backlog'
        WHEN 'done' THEN 'completed'
        WHEN 'cancelled' THEN 'canceled'
        WHEN 'canceled' THEN 'canceled'
        ELSE 'started'
      END
    SQL
  end

  def down
    remove_column :lanes, :category
  end
end
