module GhIntegration
  # Moves issues into the lane a PR automation rule points at.
  class MoveIssuesToLane < Service
    def initialize(issues:, lane:)
      @issues = issues
      @lane = lane
    end

    def call
      @issues.each do |issue|
        next if issue.lane_id == @lane.id

        issue.lane = @lane
        issue.apply_lane_timestamps!
        issue.save!
        issue.enqueue_velocity_recalculation!
        IssueAfterUpdateJob.perform_later(issue_id: issue.id, user_id: nil)
        Rails.logger.info("Moved issue #{issue.identifier} to lane '#{@lane.name}' via PR automation")
      end
    end
  end
end
