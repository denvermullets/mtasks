class ResetUserPreferencesBoardToList < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE user_preferences SET view_mode = 'list' WHERE view_mode = 'board'"
  end

  def down
    # Not reversible — we've lost which users had board saved.
  end
end
