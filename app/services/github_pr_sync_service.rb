class GithubPrSyncService
  def initialize(github_integration)
    @integration = github_integration
    @team = @integration.team
  end

  def sync_pull_request(pr_data)
    pr = find_or_initialize_pull_request(pr_data)

    # Update PR attributes
    pr.assign_attributes(
      title: pr_data['title'],
      body: pr_data['body'],
      html_url: pr_data['html_url'],
      state: pr_data['state'],
      author_login: pr_data['user']['login'],
      head_ref: pr_data['head']['ref'],
      base_ref: pr_data['base']['ref'],
      merged: pr_data['merged'] || false,
      merged_at: parse_github_time(pr_data['merged_at']),
      closed_at: parse_github_time(pr_data['closed_at']),
      github_created_at: parse_github_time(pr_data['created_at']),
      github_updated_at: parse_github_time(pr_data['updated_at'])
    )

    if pr.save
      Rails.logger.info("Synced PR ##{pr.pr_number} for integration #{@integration.id}")
      link_issues_and_queue_comments(pr, pr_data)
      pr
    else
      Rails.logger.error("Failed to sync PR ##{pr_data['number']}: #{pr.errors.full_messages.join(', ')}")
      nil
    end
  end

  private

  def find_or_initialize_pull_request(pr_data)
    @integration.pull_requests.find_or_initialize_by(pr_number: pr_data['number'])
  end

  def link_issues_and_queue_comments(pr, pr_data)
    # Parse issue references from PR title and body
    text = "#{pr_data['title']} #{pr_data['body']}"
    referenced_issues = IssueReferenceParser.find_issues(text, @team)

    return if referenced_issues.empty?

    referenced_issues.each do |issue|
      # Create or find the join record
      issue_pr = IssuePullRequest.find_or_create_by(
        issue: issue,
        pull_request: pr
      )

      # Queue comment job if not already posted
      next if issue_pr.comment_posted?

      GithubCommentPosterJob.perform_later(issue_pr.id)
    end

    Rails.logger.info("Linked #{referenced_issues.count} issues to PR ##{pr.pr_number}")
  end

  def parse_github_time(time_string)
    return nil if time_string.blank?

    Time.parse(time_string)
  rescue ArgumentError => e
    Rails.logger.warn("Failed to parse GitHub time '#{time_string}': #{e.message}")
    nil
  end
end
