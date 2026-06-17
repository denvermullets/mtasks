# Moves an issue from its current team to another team the user belongs to.
#
# Because an issue's identifier is "#{team.identifier}-#{team_number}" and
# team_number is a per-team sequential counter, the move renumbers the issue
# from the destination team's counter (the identifier changes). Team-scoped
# associations are remapped: lane is matched by name (falling back to the
# team's first lane), the assignee is kept only if still a member, and the
# project, labels, and cross-team parent/child links are cleared.
class IssueTeamMover
  attr_reader :error

  def initialize(issue:, target_team:, user:)
    @issue = issue
    @target_team = target_team
    @user = user
    @error = nil
  end

  def call
    return false unless authorized?

    Issue.transaction do
      remap_associations
      @issue.team = @target_team
      @issue.team_number = @target_team.next_issue_number
      @issue.issue_labels.destroy_all
      @issue.save!
    end

    @issue.enqueue_velocity_recalculation!
    true
  rescue ActiveRecord::RecordInvalid => e
    @error = e.record.errors.full_messages.to_sentence
    false
  end

  private

  def authorized?
    if @target_team == @issue.team
      @error = 'Issue is already in that team.'
      return false
    end

    unless member?(@issue.team) && member?(@target_team)
      @error = 'You must belong to both teams to move this issue.'
      return false
    end

    true
  end

  def remap_associations
    @issue.lane = target_lane
    @issue.assignee = nil unless @issue.assignee && member?(@target_team, @issue.assignee)
    @issue.project = nil
    sever_cross_team_hierarchy
  end

  def target_lane
    @target_team.lanes.find_by('LOWER(name) = ?', @issue.lane.name.downcase) ||
      @target_team.lanes.order(:position).first
  end

  def sever_cross_team_hierarchy
    @issue.parent_issue = nil if @issue.parent_issue && @issue.parent_issue.team_id != @target_team.id
    @issue.sub_issues.update_all(parent_issue_id: nil)
  end

  def member?(team, user = @user)
    team.users.include?(user)
  end
end
