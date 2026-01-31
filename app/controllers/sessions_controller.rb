class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  before_action :redirect_if_authenticated, only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: lambda {
    redirect_to new_session_path, alert: 'Try again later.'
  }

  def new; end

  def create
    if (user = User.authenticate_by(params.permit(:email, :password)))
      invitation_token = session[:pending_invitation_token]
      start_new_session_for user
      accept_pending_invitation(user, invitation_token)
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: 'Try another email or password.'
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private

  def accept_pending_invitation(user, token)
    return unless token

    invitation = TeamInvitation.pending.find_by(token: token)
    return unless invitation

    invitation.accept!(user)
  end
end
