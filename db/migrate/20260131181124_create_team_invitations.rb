class CreateTeamInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :team_invitations do |t|
      t.references :team, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.string :token, null: false
      t.integer :status, default: 0, null: false
      t.datetime :accepted_at

      t.timestamps
    end

    add_index :team_invitations, :token, unique: true
    add_index :team_invitations, [:team_id, :email, :status], unique: true, where: "status = 0", name: "index_team_invitations_on_team_email_pending"
  end
end
