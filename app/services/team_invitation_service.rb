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
      @notice = "#{user.name} has been added to the team."
      @success = true
    end
  end

  def invite_new_user
    @invitation = @team.team_invitations.build(email: @email, invited_by: @invited_by)

    if @invitation.save
      TeamInvitationMailer.invite(@invitation).deliver_later
      @notice = "Invitation sent to #{@email}."
      @success = true
    else
      @success = false
    end
  end
end
