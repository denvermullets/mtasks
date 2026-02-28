class AddAvatarColorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :avatar_color, :string, default: "bg-blue-600", null: false
  end
end
