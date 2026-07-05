module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :set_current_user
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**)
      skip_before_action(:require_authentication, **)
    end
  end

  private

  def current_user
    @current_user
  end

  def set_current_user
    resume_session
    @current_user = Current.user
  end

  def authenticated?
    resume_session
  end

  def require_authentication
    resume_session || request_authentication
  end

  def resume_session
    Current.session ||= find_session_by_cookie
  end

  def find_session_by_cookie
    Session.find_by(id: cookies.signed[:mtasks_session_id]) if cookies.signed[:mtasks_session_id]
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url
    redirect_to new_session_path
  end

  def after_authentication_url
    url = session.delete(:return_to_after_authenticating)
    return url if url.present?

    teams = Current.user.teams.not_archived
    team_id = teams.exists?(id: session[:current_team_id]) ? session[:current_team_id] : teams.first&.id
    team_id ? "/teams/#{team_id}/issues" : '/teams/new'
  end

  def start_new_session_for(user)
    user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
      Current.session = session
      cookies.signed.permanent[:mtasks_session_id] = { value: session.id, httponly: true, same_site: :lax }
    end
  end

  def terminate_session
    Current.session.destroy
    cookies.delete(:mtasks_session_id)
  end
end
