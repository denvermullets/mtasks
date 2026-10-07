class BackfillStartedAtForCompletedIssues < ActiveRecord::Migration[8.0]
  def up
    Issue.where(started_at: nil).where.not(completed_at: nil).update_all('started_at = completed_at')
  end

  def down
    # No-op: we can't reliably distinguish backfilled values from real ones
  end
end
