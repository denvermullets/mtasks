# Relocates an issue to another team the current user belongs to. Lives in its
# own controller because a move renumbers the issue and remaps team-scoped
# associations (see IssueTeamMover) rather than being a normal issue update.
class IssueMovesController < ApplicationController
  before_action :require_team!

  def update
    issue = Issue.find(params[:issue_id])
    target_team = user_teams.find_by(id: params[:target_team_id])
    unless target_team
      return redirect_to team_issue_path(issue.team, issue), alert: "You don't have access to that team."
    end

    mover = IssueTeamMover.new(issue: issue, target_team: target_team, user: Current.user)
    if mover.call
      track_feature('issue-transfer', 'move', entity: 'issue')
      redirect_to team_issue_path(target_team, issue), notice: "Issue moved to #{target_team.name}."
    else
      redirect_to team_issue_path(issue.team, issue), alert: mover.error || 'Could not move issue.'
    end
  end
end
