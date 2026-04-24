class TeamMembersController < ApplicationController
  before_action :require_team!

  def search
    query = params[:q].to_s.strip
    scope = current_team.users.where.not(id: Current.user.id)
    scope = scope.where('name ILIKE ?', "%#{query}%") if query.present?
    render json: scope.order(:name).limit(10).map { |u|
      { id: u.id, name: u.name }
    }
  end
end
