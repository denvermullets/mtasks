class InvitationAcceptancesController < ApplicationController
  allow_unauthenticated_access
  before_action :set_invitation

  def show
    if @invitation.accepted?
      redirect_to root_path, notice: 'This invitation has already been accepted.'
      return
    end

    if authenticated? && current_user
      # Logged in user can accept directly
      @can_accept = true
    else
      # Store token in session for post-login/registration acceptance
      session[:pending_invitation_token] = @invitation.token
      @can_accept = false
    end
  end

  def update
    if @invitation.accepted?
      redirect_to root_path, notice: 'This invitation has already been accepted.'
      return
    end

    unless authenticated? && current_user
      session[:pending_invitation_token] = @invitation.token
      redirect_to new_session_path, notice: 'Please log in to accept the invitation.'
      return
    end

    @invitation.accept!(current_user)
    session.delete(:pending_invitation_token)
    redirect_to team_issues_path(@invitation.team), notice: "You've joined #{@invitation.team.name}!"
  end

  private

  def set_invitation
    @invitation = TeamInvitation.pending.find_by!(token: params[:token])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: 'Invitation not found or has already been used.'
  end
end
