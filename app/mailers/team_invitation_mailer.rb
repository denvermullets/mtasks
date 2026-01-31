class TeamInvitationMailer < ApplicationMailer
  def invite(team_invitation)
    @invitation = team_invitation
    @team = team_invitation.team
    @inviter = team_invitation.invited_by
    @accept_url = invitation_url(token: @invitation.token)

    mail(
      to: @invitation.email,
      subject: "You've been invited to join #{@team.name}"
    )
  end

  def added_to_team(user, team, added_by)
    @user = user
    @team = team
    @added_by = added_by
    @team_url = team_issues_url(team)

    mail(
      to: user.email,
      subject: "You've been added to #{team.name}"
    )
  end
end
