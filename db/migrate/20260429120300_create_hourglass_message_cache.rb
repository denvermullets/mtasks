class CreateHourglassMessageCache < ActiveRecord::Migration[8.1]
  def change
    create_table :hourglass_message_cache do |t|
      t.string :hourglass_message_id, null: false
      t.string :hourglass_channel_id, null: false
      t.string :hourglass_thread_id
      t.string :hourglass_user_id
      t.string :author_email
      t.string :author_display_name
      t.text :body
      t.string :message_type
      t.datetime :pinned_at
      t.string :pinned_by_email
      t.datetime :edited_at
      t.string :source, null: false
      t.datetime :posted_at, null: false
      t.datetime :deleted_at
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :hourglass_message_cache, :hourglass_message_id, unique: true
    add_index :hourglass_message_cache, %i[hourglass_channel_id posted_at]
    add_index :hourglass_message_cache, %i[hourglass_thread_id posted_at]
  end
end
