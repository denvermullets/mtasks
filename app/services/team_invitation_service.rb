class TeamInvitationService < Service
  attr_reader :notice, :error, :invitation

  def initialize(team:, email:, invited_by:)
    @team = team
    @email = email&.strip&.downcase
    @invited_by = invited_by
  end

  def call
    existing_user = User.find_by(email: @email)

    if existing_user
      add_existing_user(existing_user)
    else
      invite_new_user
    end

    self
  end

  def success? = @success

  private

  def add_existing_user(user)
    if @team.users.include?(user)
      @error = "#{@email} is already a member of this team."
      @success = false
    else
      @team.team_memberships.create!(user: user)
      TeamInvitationMailer.added_to_team(user, @team, @invited_by).deliver_later
      log_existing_user_added(user) if Rails.env.development?
      @notice = "#{user.name} has been added to the team."
      @success = true
    end
  end

  def invite_new_user
    @invitation = @team.team_invitations.build(email: @email, invited_by: @invited_by)

    if @invitation.save
      TeamInvitationMailer.invite(@invitation).deliver_later
      log_invitation_url if Rails.env.development?
      @notice = "Invitation sent to #{@email}."
      @success = true
    else
      @success = false
    end
  end

  def log_invitation_url
    host = Rails.application.config.action_mailer.default_url_options
    url = Rails.application.routes.url_helpers.invitation_url(token: @invitation.token, **host)
    banner = '=' * 80
    Rails.logger.info "\n\n#{banner}\n  INVITATION for #{@email}\n  #{url}\n#{banner}\n\n"
  end

  def log_existing_user_added(user)
    banner = '=' * 80
    Rails.logger.info "\n\n#{banner}\n  ADDED EXISTING USER #{user.name} (#{user.email}) to team " \
                      "#{@team.name} — no URL needed, they can log in and see it.\n#{banner}\n\n"
  end
end
