class TeamInvitationsController < ApplicationController
  before_action :set_team
  before_action :require_team_admin_for_team

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

  def resend
    @invitation = @team.team_invitations.pending.find(params[:id])
    TeamInvitationMailer.invite(@invitation).deliver_later
    redirect_to team_team_invitations_path(@team), notice: "Invitation resent to #{@invitation.email}."
  end

  def remove_member
    member = @team.users.find(params[:member_id])
    if @team.owner?(member)
      redirect_to team_team_invitations_path(@team), alert: 'Cannot remove the team owner. Transfer ownership first.'
      return
    end
    @team.team_memberships.find_by!(user: member).destroy
    redirect_to team_team_invitations_path(@team), notice: "#{member.name} has been removed from the team."
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def require_team_admin_for_team
    require_team_admin!(@team)
  end

  def invitation_params
    params.require(:team_invitation).permit(:email)
  end
end
