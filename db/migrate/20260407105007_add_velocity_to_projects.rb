class AddVelocityToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :velocity_score, :integer, default: 0, null: false
    add_column :projects, :completed_issues_count, :integer, default: 0, null: false
    add_column :projects, :total_issues_count, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        Project.find_each(&:recalculate_velocity!)
      end
    end
  end
end
