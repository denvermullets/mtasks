class ExtendHourglassLinksForStatus < ActiveRecord::Migration[8.1]
  def change
    add_column :hourglass_links, :status, :string, default: 'active', null: false
    add_column :hourglass_links, :hourglass_channel_name, :string
    add_reference :hourglass_links, :hourglass_integration, foreign_key: true, null: true
    add_index :hourglass_links, :status
  end
end
