class AddSubGroupingToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :sub_group_by, :string, default: 'none'
    add_column :user_preferences, :show_empty_rows, :boolean, default: false
  end
end
