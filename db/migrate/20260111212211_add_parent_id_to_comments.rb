class AddParentIdToComments < ActiveRecord::Migration[8.1]
  def change
    add_reference :comments, :parent, null: true, foreign_key: { to_table: :comments }
  end
end
