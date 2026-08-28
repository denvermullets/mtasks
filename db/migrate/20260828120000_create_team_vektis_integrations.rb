class CreateTeamVektisIntegrations < ActiveRecord::Migration[8.1]
  def change
    create_table :team_vektis_integrations do |t|
      t.references :team, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :publishable_key
      t.string :server_key
      # Deliberately not indexed or unique: the same VEKTIS customer id may legitimately be
      # shared by several teams.
      t.string :customer_id
      t.references :connected_by_user, foreign_key: { to_table: :users }
      t.datetime :connected_at

      t.timestamps
    end
  end
end
