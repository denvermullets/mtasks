class UsersController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  before_action :redirect_if_authenticated, only: %i[new create]

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      invitation_token = session[:pending_invitation_token]
      start_new_session_for @user
      accept_pending_invitation(@user, invitation_token)
      redirect_to root_path, notice: 'Welcome! Your account has been created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  def accept_pending_invitation(user, token)
    return unless token

    invitation = TeamInvitation.pending.find_by(token: token)
    return unless invitation

    invitation.accept!(user)
  end
end
