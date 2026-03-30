module Api
  module V1
    class TeamsController < BaseController
      def index
        teams = current_user.teams.not_archived.order(:name)
        render json: teams.map { |t|
          { id: t.id, name: t.name, identifier: t.identifier }
        }
      end
    end
  end
end
