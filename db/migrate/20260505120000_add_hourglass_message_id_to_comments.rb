class AddHourglassMessageIdToComments < ActiveRecord::Migration[8.1]
  def change
    add_column :comments, :hourglass_message_id, :string
    add_index :comments, :hourglass_message_id, unique: true, where: 'hourglass_message_id IS NOT NULL'
  end
end
