class GithubCommentPosterJob < ApplicationJob
  queue_as :default

  retry_on GithubApiClient::RateLimitError, wait: 5.minutes, attempts: 3
  retry_on GithubApiClient::ApiError, wait: :exponentially_longer, attempts: 5

  def perform(issue_pull_request_id)
    issue_pr = IssuePullRequest.find_by(id: issue_pull_request_id)

    unless issue_pr
      Rails.logger.error("IssuePullRequest #{issue_pull_request_id} not found")
      return
    end

    # Skip if already posted
    return if issue_pr.comment_posted?

    issue = issue_pr.issue
    pr = issue_pr.pull_request
    subscription = pr.github_repository_subscription

    # Build comment body
    comment_body = build_comment_body(issue)

    # Post comment via GitHub API
    api_client = GithubApiClient.new(subscription)
    api_client.post_pr_comment(pr.pr_number, comment_body)

    # Mark as posted
    issue_pr.update!(
      comment_posted: true,
      comment_posted_at: Time.current
    )

    Rails.logger.info("Posted comment to PR ##{pr.pr_number} for issue #{issue.identifier}")
    track_comment_posted(issue_pr)
  end

  private

  # The outbound half of the GitHub integration — no delivery guid, so the key is the record the
  # job already treats as its unit of work. Together with the `comment_posted?` guard above that
  # makes a retry a no-op end to end, including the window where the API call succeeded and the
  # stamp did not.
  def track_comment_posted(issue_pr)
    Vektis::EventEmitter.integration(
      'github-integration', 'sync',
      provider: 'github', via: 'job',
      key: ['issue_pull_request', issue_pr.id],
      properties: { entity: 'issue' }
    )
  end

  def build_comment_body(issue)
    app_url = Rails.application.routes.url_helpers.team_issue_url(
      issue.team,
      issue,
      host: ENV.fetch('APP_HOST', 'localhost:3000'),
      protocol: Rails.env.production? ? 'https' : 'http'
    )

    <<~COMMENT
      ## Linked Issue: [#{issue.identifier}](#{app_url})

      **Title:** #{issue.title}
      **Status:** #{issue.lane.name}
      **Priority:** #{issue.priority&.humanize || 'Not set'}

      This pull request has been automatically linked to the issue.
    COMMENT
  end
end
