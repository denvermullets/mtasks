class ChangeUserPreferencesViewModeDefaultToList < ActiveRecord::Migration[8.1]
  def up
    change_column_default :user_preferences, :view_mode, from: 'board', to: 'list'
  end

  def down
    change_column_default :user_preferences, :view_mode, from: 'list', to: 'board'
  end
end
