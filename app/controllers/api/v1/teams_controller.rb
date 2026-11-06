module Api
  module V1
    class TeamsController < BaseController
      def index
        teams = accessible_teams.order(:name).to_a
        admin_team_ids = current_user.team_memberships.admin.where(team_id: teams.map(&:id)).pluck(:team_id).to_set

        render json: teams.map { |t|
          { id: t.id, name: t.name, identifier: t.identifier, role: role_for(t, admin_team_ids) }
        }
      end

      private

      # Same precedence as Team#owner? / Team#admin?, resolved from one membership query rather than one per team.
      def role_for(team, admin_team_ids)
        return 'owner' if team.owner?(current_user)
        return 'admin' if admin_team_ids.include?(team.id)

        'member'
      end
    end
  end
end
