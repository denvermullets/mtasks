# The VEK-585 call sites for GithubPrSyncService, kept out of the service for the same reason
# VektisIssueTracking is kept out of IssuesController: the service is already at 141 of its 150
# allowed lines, and the emission rules are long enough to bury the sync logic.
#
# Everything here is webhook-originated, so every event carries a deterministic event_id derived
# from the GitHub delivery guid (§8). GitHub redelivers — on its own retry schedule and from the
# "Redeliver" button — and a random id would file each redelivery as fresh activity.
module Vektis
  module GithubTracking
    private

    # One event per delivery per PR, not one per issue: attaching three issues to a PR in one
    # webhook is one linking gesture with `count: 3`, exactly as a bulk label save is (§5.2).
    def track_issues_linked(pull_request, newly_linked)
      return if newly_linked.empty?

      track_github('github-integration', 'link', pull_request.id,
                   entity: 'issue', count: newly_linked.size)
    end

    # Taxonomy §4.5: a merged PR can complete an issue with no user in any page. That produces two
    # genuinely different facts — an issue completed, and the GitHub integration completed one —
    # and they are separate feature_ids, so §9's per-pair rule is satisfied, not bent.
    def track_lane_automation(issue)
      action = Vektis::IssueProperties.workflow_action(issue)
      properties = Vektis::IssueProperties.lane_move(issue)
                                          .merge(Vektis::IssueProperties.shape(issue))

      track_github('issue-workflow', action, issue.id, **properties)
      return unless action == 'complete'

      track_github('github-integration', 'complete', issue.id, entity: 'issue')
    end

    # The record id joins the idempotency key rather than the properties: one delivery can close
    # several issues, and without the discriminator all but the first would collapse onto a single
    # event_id and be dropped by vanalytics as duplicates (§8, as amended by VEK-585).
    def track_github(feature_id, action, subject, **properties)
      Vektis::EventEmitter.integration(
        feature_id, action,
        provider: 'github', via: 'webhook',
        key: [@delivery_id, subject],
        properties: properties.compact
      )
    end
  end
end
