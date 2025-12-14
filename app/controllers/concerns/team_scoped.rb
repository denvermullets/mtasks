module TeamScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_current_team, if: :authenticated?
    helper_method :current_team, :user_teams
  end

  private

  def current_team
    @current_team
  end

  def user_teams
    @user_teams ||= current_user.teams.includes(:workspace)
  end

  def set_current_team
    team_id = params[:team_id] || session[:current_team_id]

    @current_team = if team_id
                      user_teams.find_by(id: team_id)
                    else
                      user_teams.first
                    end

    session[:current_team_id] = @current_team&.id
  end

  def authorize_team_access!(team)
    return if user_teams.include?(team)

    redirect_to root_path, alert: "You don't have access to that team"
  end

  def require_team!
    redirect_to new_team_path, alert: 'Please create or join a team first' unless current_team
  end

  def require_admin!
    redirect_to root_path, alert: 'You must be an admin' unless current_user&.admin?
  end
end
