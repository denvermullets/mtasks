class TeamInvitationsController < ApplicationController
  before_action :set_team
  before_action :require_workspace_owner

  def index
    @members = @team.users.order(:name)
    @pending_invitations = @team.team_invitations.pending.includes(:invited_by).order(created_at: :desc)
  end

  def create
    result = TeamInvitationService.call(team: @team, email: invitation_params[:email], invited_by: current_user)

    if result.success?
      redirect_to team_team_invitations_path(@team), notice: result.notice
    elsif result.invitation
      @invitation = result.invitation
      @members = @team.users.order(:name)
      @pending_invitations = @team.team_invitations.pending.includes(:invited_by).order(created_at: :desc)
      render :index, status: :unprocessable_entity
    else
      redirect_to team_team_invitations_path(@team), alert: result.error
    end
  end

  def destroy
    @invitation = @team.team_invitations.pending.find(params[:id])
    @invitation.destroy
    redirect_to team_team_invitations_path(@team), notice: 'Invitation revoked.'
  end

  def remove_member
    member = @team.users.find(params[:member_id])
    if member.id == @team.workspace.owner_id
      redirect_to team_team_invitations_path(@team), alert: 'Cannot remove the workspace owner.'
      return
    end
    @team.team_memberships.find_by!(user: member).destroy
    redirect_to team_team_invitations_path(@team), notice: "#{member.name} has been removed from the team."
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def require_workspace_owner
    return if workspace_owner?(@team)

    redirect_to root_path, alert: "You don't have permission to manage team members."
  end

  def invitation_params
    params.require(:team_invitation).permit(:email)
  end
end
