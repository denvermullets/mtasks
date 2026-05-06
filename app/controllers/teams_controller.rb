class TeamsController < ApplicationController
  include TeamScoped

  before_action :set_team, only: %i[edit update confirm_archive archive]
  before_action :authorize_team_admin!, only: %i[edit update confirm_archive archive]

  def new
    @team = Team.new
  end

  def create
    workspace = current_user.personal_workspace
    @team = workspace.teams.build(team_params.merge(owner: current_user))

    if @team.save
      setup_team_membership
      redirect_to team_issues_path(@team), notice: 'Team created successfully!'
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

  def confirm_archive
    @issue_count = @team.issues.not_archived.count
  end

  def archive
    @team.archive!
    session.delete(:current_team_id)
    redirect_to root_path, notice: "Team \"#{@team.name}\" has been archived"
  end

  private

  def set_team
    @team = Team.find(params[:id])
    authorize_team_access!(@team)
  end

  def authorize_team_admin!
    require_team_admin!(@team)
  end

  def team_params
    params.require(:team).permit(:name, :identifier, :description)
  end

  def team_update_params
    params.require(:team).permit(:name, :identifier)
  end

  def setup_team_membership
    @team.team_memberships.create!(user: current_user, role: :admin)
    session[:current_team_id] = @team.id
  end
end
