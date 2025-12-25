class GithubCommentProcessorJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(integration_id, pr_number, comment_body)
    integration = GithubIntegration.find_by(id: integration_id)

    unless integration
      Rails.logger.error("GithubIntegration #{integration_id} not found")
      return
    end

    pull_request = find_or_fetch_pull_request(integration, pr_number)
    return unless pull_request

    link_referenced_issues(integration.team, pull_request, pr_number, comment_body)
  end

  private

  def find_or_fetch_pull_request(integration, pr_number)
    pull_request = integration.pull_requests.find_by(pr_number: pr_number)
    return pull_request if pull_request

    fetch_pull_request_from_github(integration, pr_number)
  end

  def fetch_pull_request_from_github(integration, pr_number)
    Rails.logger.info("PR ##{pr_number} not found locally, fetching from GitHub")

    client = Octokit::Client.new(access_token: integration.access_token)
    pr_data = client.pull_request(integration.github_repo_full_name, pr_number)

    sync_service = GithubPrSyncService.new(integration)
    sync_service.sync_pull_request(pr_data.to_h)
  rescue StandardError => e
    Rails.logger.error("Failed to fetch PR ##{pr_number}: #{e.message}")
    nil
  end

  def link_referenced_issues(team, pull_request, pr_number, comment_body)
    referenced_issues = IssueReferenceParser.find_issues(comment_body, team)

    if referenced_issues.empty?
      Rails.logger.info("No issue references found in comment for PR ##{pr_number}")
      return
    end

    queue_comment_jobs_for_issues(referenced_issues, pull_request)
    Rails.logger.info("Linked #{referenced_issues.count} issues from comment to PR ##{pr_number}")
  end

  def queue_comment_jobs_for_issues(referenced_issues, pull_request)
    referenced_issues.each do |issue|
      issue_pr = IssuePullRequest.find_or_create_by(
        issue: issue,
        pull_request: pull_request
      )

      next if issue_pr.comment_posted?

      GithubCommentPosterJob.perform_later(issue_pr.id)
    end
  end
end
