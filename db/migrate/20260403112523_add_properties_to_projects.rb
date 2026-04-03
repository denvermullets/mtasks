class AddPropertiesToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :priority, :integer, default: 4
    add_column :projects, :status, :string, default: "backlog"
    add_reference :projects, :lead, foreign_key: { to_table: :users }, null: true
    add_column :projects, :start_date, :date
    add_column :projects, :due_date, :date

    create_table :project_labels do |t|
      t.references :project, null: false, foreign_key: true
      t.references :label, null: false, foreign_key: true
      t.timestamps
    end
  end
end
