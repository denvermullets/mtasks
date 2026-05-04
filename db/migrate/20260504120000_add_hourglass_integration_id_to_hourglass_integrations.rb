class AddHourglassIntegrationIdToHourglassIntegrations < ActiveRecord::Migration[8.0]
  def change
    add_column :hourglass_integrations, :hourglass_integration_id, :integer
    add_index :hourglass_integrations, :hourglass_integration_id
  end
end
