class BackfillCompletedAtForDoneIssues < ActiveRecord::Migration[8.1]
  def up
    done_lane_ids = Lane.where('LOWER(name) = ?', 'done').pluck(:id)
    Issue.where(lane_id: done_lane_ids, completed_at: nil).find_each do |issue|
      issue.update_column(:completed_at, issue.updated_at)
    end
  end

  def down
    # No-op: we can't reliably distinguish backfilled values from real ones
  end
end
