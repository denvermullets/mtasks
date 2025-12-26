class ChangeGroupByDefaultToStatus < ActiveRecord::Migration[8.1]
  def change
    change_column_default :user_preferences, :group_by, from: 'lane', to: 'status'
  end
end
