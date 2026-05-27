class BackfillTeamMembershipAdmins < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    execute(<<~SQL)
      INSERT INTO team_memberships (team_id, user_id, role, created_at, updated_at)
      SELECT t.id, w.owner_id, 1, NOW(), NOW()
      FROM teams t
      JOIN workspaces w ON w.id = t.workspace_id
      WHERE NOT EXISTS (
        SELECT 1 FROM team_memberships tm
        WHERE tm.team_id = t.id AND tm.user_id = w.owner_id
      )
    SQL

    execute(<<~SQL)
      UPDATE team_memberships tm
      SET role = 1, updated_at = NOW()
      FROM teams t
      JOIN workspaces w ON w.id = t.workspace_id
      WHERE tm.team_id = t.id AND tm.user_id = w.owner_id AND tm.role <> 1
    SQL
  end

  def down
    execute('UPDATE team_memberships SET role = 0')
  end
end
