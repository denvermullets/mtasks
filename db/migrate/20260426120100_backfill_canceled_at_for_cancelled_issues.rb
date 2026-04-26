class BackfillCanceledAtForCancelledIssues < ActiveRecord::Migration[8.0]
  def up
    canceled_lane_ids = Lane.where('LOWER(name) IN (?)', %w[cancelled canceled]).pluck(:id)
    Issue.where(lane_id: canceled_lane_ids, canceled_at: nil).find_each do |issue|
      issue.update_column(:canceled_at, issue.updated_at)
    end
  end

  def down
    # No-op: we can't reliably distinguish backfilled values from real ones
  end
end
