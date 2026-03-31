module Api
  module V1
    class MembersController < BaseController
      before_action :set_current_team

      def index
        members = current_team.users.order(:name)
        render json: members.map { |u|
          { id: u.id, name: u.name, email: u.email }
        }
      end
    end
  end
end
