class TeamsController < ApplicationController
  def new
    @workspace = Workspace.new
    @team = Team.new
  end

  def create
    # Create workspace if user doesn't have one
    @workspace = current_user.owned_workspaces.first_or_create!(workspace_params)

    # Create team
    @team = @workspace.teams.build(team_params)

    if @team.save
      # Add current user to the team
      @team.team_memberships.create!(user: current_user)
      redirect_to root_path, notice: "Team created successfully!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name).merge(owner: current_user)
  end

  def team_params
    params.require(:team).permit(:name, :identifier, :description)
  end
end
