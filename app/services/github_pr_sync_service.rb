class GithubPrSyncService
  def initialize(github_repository_subscription)
    @subscription = github_repository_subscription
    @team = @subscription.team
  end

  def sync_pull_request(pr_data, action: nil)
    pull_request = find_or_initialize_pull_request(pr_data)
    pull_request.assign_attributes(build_pr_attributes(pr_data))

    if pull_request.save
      Rails.logger.info("Synced PR ##{pull_request.pr_number} for team #{@team.identifier}")
      link_issues_and_queue_comments(pull_request, pr_data)
      apply_automation_rules(pull_request, action) if action
      pull_request
    else
      Rails.logger.error("Failed to sync PR ##{pr_data['number']}: #{pull_request.errors.full_messages.join(', ')}")
      nil
    end
  end

  private

  def find_or_initialize_pull_request(pr_data)
    @subscription.pull_requests.find_or_initialize_by(pr_number: pr_data['number'])
  end

  def build_pr_attributes(pr_data)
    {
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
    }
  end

  def link_issues_and_queue_comments(pull_request, pr_data)
    # Parse issue references from PR title, body, and branch name
    text = "#{pr_data['title']} #{pr_data['body']} #{pr_data.dig('head', 'ref')}"
    referenced_issues = IssueReferenceParser.find_issues(text, @team)

    return if referenced_issues.empty?

    referenced_issues.each do |issue|
      # Create or find the join record
      issue_pr = IssuePullRequest.find_or_create_by(
        issue: issue,
        pull_request: pull_request
      )

      # Queue comment job if not already posted
      next if issue_pr.comment_posted?

      GithubCommentPosterJob.perform_later(issue_pr.id)
    end

    Rails.logger.info("Linked #{referenced_issues.count} issues to PR ##{pull_request.pr_number}")
  end

  def apply_automation_rules(pull_request, action)
    trigger = determine_trigger(action, pull_request)
    return unless trigger

    rules = @subscription.pr_automation_rules.where(trigger: trigger)

    rules = rules.select { |rule| File.fnmatch(rule.branch_pattern, pull_request.base_ref) } if trigger == 'pr_merged'

    return if rules.empty?

    rule = rules.first
    move_linked_issues_to_lane(pull_request, rule.lane)
  end

  def determine_trigger(action, pull_request)
    case action
    when 'opened', 'reopened'
      'pr_opened'
    when 'closed'
      pull_request.merged? ? 'pr_merged' : 'pr_closed'
    end
  end

  def move_linked_issues_to_lane(pull_request, lane)
    pull_request.issues.each do |issue|
      next if issue.lane_id == lane.id

      issue.lane = lane
      issue.apply_lane_timestamps!
      issue.save!
      Rails.logger.info("Moved issue #{issue.identifier} to lane '#{lane.name}' via PR automation")
    end
  end

  def parse_github_time(time_string)
    return nil if time_string.blank?

    Time.parse(time_string)
  rescue ArgumentError => e
    Rails.logger.warn("Failed to parse GitHub time '#{time_string}': #{e.message}")
    nil
  end
end
