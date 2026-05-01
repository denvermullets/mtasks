class AddCallbackApiTokenToHourglassIntegrations < ActiveRecord::Migration[8.1]
  def change
    add_reference :hourglass_integrations, :callback_api_token,
                  foreign_key: { to_table: :api_tokens }, null: true
  end
end
