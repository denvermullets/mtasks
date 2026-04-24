class AddSettingsToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :settings, :jsonb, default: {}, null: false
    remove_column :users, :avatar_color
  end

  def down
    remove_column :users, :settings
    add_column :users, :avatar_color, :string, default: 'bg-blue-600', null: false
  end
end
