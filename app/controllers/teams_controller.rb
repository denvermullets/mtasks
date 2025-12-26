class TeamsController < ApplicationController
  include TeamScoped

  before_action :set_team, only: %i[edit update]
  before_action :authorize_team_membership!, only: %i[edit update]

  def new
    @workspace = Workspace.new
    @team = Team.new
  end

  def create
    # Get or create workspace
    @workspace = if params[:workspace].present?
                   # New user creating first workspace and team
                   current_user.owned_workspaces.first_or_create!(workspace_params)
                 else
                   # Existing user adding a team
                   current_user.owned_workspaces.first
                 end

    # Create team
    @team = @workspace.teams.build(team_params)

    if @team.save
      # Add current user to the team
      @team.team_memberships.create!(user: current_user)
      redirect_to root_path, notice: 'Team created successfully!'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @lanes = @team.lanes.order(:position)
  end

  def update
    if @team.update(team_update_params)
      redirect_to edit_team_path(@team), notice: 'Team updated successfully'
    else
      @lanes = @team.lanes.order(:position)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_team
    @team = Team.find(params[:id])
    authorize_team_access!(@team)
  end

  def authorize_team_membership!
    return if @team.users.include?(Current.user)

    redirect_to root_path, alert: "You don't have permission to modify this team"
  end

  def workspace_params
    params.require(:workspace).permit(:name).merge(owner: current_user)
  end

  def team_params
    params.require(:team).permit(:name, :identifier, :description)
  end

  def team_update_params
    params.require(:team).permit(:name, :identifier)
  end
end
