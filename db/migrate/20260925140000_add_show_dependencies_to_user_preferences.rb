class AddShowDependenciesToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :show_dependencies, :boolean, default: false, null: false
  end
end
