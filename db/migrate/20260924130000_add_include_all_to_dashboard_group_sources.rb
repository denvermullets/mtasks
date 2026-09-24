# Sources default to "assigned to me"; include_all opts a team or project into every issue.
class AddIncludeAllToDashboardGroupSources < ActiveRecord::Migration[8.1]
  def change
    add_column :dashboard_group_sources, :include_all, :boolean, null: false, default: false
  end
end
