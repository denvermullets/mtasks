class CreateHourglassLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :hourglass_links do |t|
      t.string :link_type, null: false
      t.references :team, null: false, foreign_key: true
      t.references :mtasks_project, foreign_key: { to_table: :projects }
      t.references :mtasks_issue, foreign_key: { to_table: :issues }
      t.string :mtasks_issue_identifier
      t.string :hourglass_channel_id
      t.string :hourglass_thread_id
      t.references :created_by_user, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :hourglass_links, :mtasks_project_id,
              unique: true,
              where: "link_type = 'project_channel'",
              name: 'idx_hg_links_project_unique'
    add_index :hourglass_links, :mtasks_issue_id,
              unique: true,
              where: "link_type = 'issue_thread'",
              name: 'idx_hg_links_issue_unique'
    add_index :hourglass_links, :hourglass_channel_id,
              unique: true,
              where: "link_type = 'project_channel'",
              name: 'idx_hg_links_channel_unique'
    add_index :hourglass_links, :hourglass_thread_id,
              unique: true,
              where: "link_type = 'issue_thread'",
              name: 'idx_hg_links_thread_unique'
  end
end
