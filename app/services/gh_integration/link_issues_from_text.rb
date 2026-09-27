module GhIntegration
  # Links every issue referenced in text to the PR, then applies the pr_opened rule to
  # the issues that were not already linked. Callers pass PR title/body/branch or a comment body.
  # Returns the issues this call newly attached.
  class LinkIssuesFromText < Service
    def initialize(subscription:, pull_request:, text:)
      @subscription = subscription
      @pull_request = pull_request
      @text = text
    end

    def call
      newly_linked = link_issues
      apply_new_link_automation(newly_linked)
      newly_linked
    end

    private

    def link_issues
      referenced_issues = IssueReferenceParser.find_issues(@text, @subscription.team)

      return [] if referenced_issues.empty?

      newly_linked = referenced_issues.select { |issue| link_issue(issue) }

      Rails.logger.info(
        "Linked #{referenced_issues.count} issues to PR ##{@pull_request.pr_number} " \
        "(#{newly_linked.count} newly attached)"
      )
      newly_linked
    end

    # Returns true when this call is what attached the issue to the PR.
    def link_issue(issue)
      issue_pr = IssuePullRequest.find_or_initialize_by(
        issue: issue,
        pull_request: @pull_request
      )
      newly_linked = issue_pr.new_record?
      issue_pr.save! if newly_linked

      # Queue comment job if not already posted
      GithubCommentPosterJob.perform_later(issue_pr.id) unless issue_pr.comment_posted?

      newly_linked
    end

    # An issue can be attached long after the PR is opened - by a title edit, a new commit, or a
    # comment - so the pr_opened rule has to fire on attachment rather than only on the opened webhook.
    def apply_new_link_automation(newly_linked)
      return if newly_linked.empty?
      return unless @pull_request.state == 'open' && !@pull_request.merged?

      rule = @subscription.pr_automation_rules.find_by(trigger: 'pr_opened')
      return unless rule

      MoveIssuesToLane.call(issues: newly_linked, lane: rule.lane)
    end
  end
end
