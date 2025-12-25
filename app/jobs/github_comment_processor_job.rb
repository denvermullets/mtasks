class GithubCommentProcessorJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(integration_id, pr_number, comment_body)
    integration = GithubIntegration.find_by(id: integration_id)

    unless integration
      Rails.logger.error("GithubIntegration #{integration_id} not found")
      return
    end

    team = integration.team

    # Find or create the PR record
    pr = integration.pull_requests.find_by(pr_number: pr_number)

    unless pr
      # If PR doesn't exist yet, we need to fetch it from GitHub and create it
      Rails.logger.info("PR ##{pr_number} not found locally, fetching from GitHub")

      begin
        client = Octokit::Client.new(access_token: integration.access_token)
        pr_data = client.pull_request(integration.github_repo_full_name, pr_number)

        # Create the PR using the sync service
        sync_service = GithubPrSyncService.new(integration)
        pr = sync_service.sync_pull_request(pr_data.to_h)
      rescue StandardError => e
        Rails.logger.error("Failed to fetch PR ##{pr_number}: #{e.message}")
        return
      end
    end

    return unless pr

    # Parse issue references from comment
    referenced_issues = IssueReferenceParser.find_issues(comment_body, team)

    if referenced_issues.empty?
      Rails.logger.info("No issue references found in comment for PR ##{pr_number}")
      return
    end

    # Link new issues to the PR
    referenced_issues.each do |issue|
      issue_pr = IssuePullRequest.find_or_create_by(
        issue: issue,
        pull_request: pr
      )

      # Queue comment job if not already posted
      next if issue_pr.comment_posted?

      GithubCommentPosterJob.perform_later(issue_pr.id)
    end

    Rails.logger.info("Linked #{referenced_issues.count} issues from comment to PR ##{pr_number}")
  end
end
