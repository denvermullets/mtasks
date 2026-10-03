class CreateApiTokenTeams < ActiveRecord::Migration[8.1]
  def up
    create_table :api_token_teams do |t|
      t.references :api_token, null: false, foreign_key: true, index: false
      t.references :team, null: false, foreign_key: true
      t.timestamps
    end
    add_index :api_token_teams, %i[api_token_id team_id], unique: true

    # An empty team set has to mean "no teams", not "every team": otherwise removing a token's last
    # team silently widens it to everything the user can reach. The flag carries that distinction.
    add_column :api_tokens, :team_scoped, :boolean, null: false, default: false

    execute <<~SQL.squish
      INSERT INTO api_token_teams (api_token_id, team_id, created_at, updated_at)
      SELECT id, team_id, NOW(), NOW() FROM api_tokens WHERE team_id IS NOT NULL
    SQL
    execute 'UPDATE api_tokens SET team_scoped = TRUE WHERE team_id IS NOT NULL'
  end

  def down
    remove_column :api_tokens, :team_scoped
    drop_table :api_token_teams
  end
end
