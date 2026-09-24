class CreateDashboards < ActiveRecord::Migration[8.1]
  def change
    create_dashboards
    create_dashboard_groups
    create_dashboard_group_sources

    add_index :issues, %i[team_id due_date],
              where: 'archived_at IS NULL AND completed_at IS NULL AND canceled_at IS NULL',
              name: 'index_issues_on_team_id_due_date_open'
  end

  private

  def create_dashboards
    create_table :dashboards do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :dashboards, %i[user_id position]
  end

  def create_dashboard_groups
    create_table :dashboard_groups do |t|
      t.references :dashboard, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :color, null: false, default: '#6366f1'
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :dashboard_groups, %i[dashboard_id position]
  end

  def create_dashboard_group_sources
    create_table :dashboard_group_sources do |t|
      t.references :dashboard_group, null: false, foreign_key: true
      t.references :source, polymorphic: true, null: false
      t.timestamps
    end
    add_index :dashboard_group_sources, %i[dashboard_group_id source_type source_id],
              unique: true, name: 'index_dashboard_group_sources_uniqueness'
  end
end
