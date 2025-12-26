class ChangeShowEmptyGroupsDefaultToTrue < ActiveRecord::Migration[8.1]
  def change
    change_column_default :user_preferences, :show_empty_groups, from: false, to: true
  end
end
