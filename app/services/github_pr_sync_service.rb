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
      link_issues_from_text(pull_request, issue_reference_text(pr_data))
      apply_automation_rules(pull_request, action) if action
      pull_request
    else
      Rails.logger.error("Failed to sync PR ##{pr_data['number']}: #{pull_request.errors.full_messages.join(', ')}")
      nil
    end
  end

  # Links every issue referenced in text to the PR, then applies the pr_opened rule to
  # the issues that were not already linked. Callers pass PR title/body/branch or a comment body.
  def link_issues_from_text(pull_request, text)
    newly_linked = link_issues(pull_request, text)
    apply_new_link_automation(pull_request, newly_linked)
    newly_linked
  end

  private

  def issue_reference_text(pr_data)
    "#{pr_data['title']} #{pr_data['body']} #{pr_data.dig('head', 'ref')}"
  end

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

  def link_issues(pull_request, text)
    referenced_issues = IssueReferenceParser.find_issues(text, @team)

    return [] if referenced_issues.empty?

    newly_linked = referenced_issues.select { |issue| link_issue(issue, pull_request) }

    Rails.logger.info(
      "Linked #{referenced_issues.count} issues to PR ##{pull_request.pr_number} " \
      "(#{newly_linked.count} newly attached)"
    )
    newly_linked
  end

  # Returns true when this call is what attached the issue to the PR.
  def link_issue(issue, pull_request)
    issue_pr = IssuePullRequest.find_or_initialize_by(
      issue: issue,
      pull_request: pull_request
    )
    newly_linked = issue_pr.new_record?
    issue_pr.save! if newly_linked

    # Queue comment job if not already posted
    GithubCommentPosterJob.perform_later(issue_pr.id) unless issue_pr.comment_posted?

    newly_linked
  end

  # An issue can be attached long after the PR is opened - by a title edit, a new commit, or a
  # comment - so the pr_opened rule has to fire on attachment rather than only on the opened webhook.
  def apply_new_link_automation(pull_request, newly_linked)
    return if newly_linked.empty?
    return unless pull_request.state == 'open' && !pull_request.merged?

    rule = @subscription.pr_automation_rules.find_by(trigger: 'pr_opened')
    return unless rule

    move_issues_to_lane(newly_linked, rule.lane)
  end

  def apply_automation_rules(pull_request, action)
    trigger = determine_trigger(action, pull_request)
    return unless trigger

    rules = @subscription.pr_automation_rules.where(trigger: trigger)

    rules = rules.select { |rule| File.fnmatch(rule.branch_pattern, pull_request.base_ref) } if trigger == 'pr_merged'

    return if rules.empty?

    rule = rules.first
    move_issues_to_lane(pull_request.issues, rule.lane)
  end

  def determine_trigger(action, pull_request)
    case action
    when 'opened', 'reopened'
      'pr_opened'
    when 'closed'
      pull_request.merged? ? 'pr_merged' : 'pr_closed'
    end
  end

  def move_issues_to_lane(issues, lane)
    issues.each do |issue|
      next if issue.lane_id == lane.id

      issue.lane = lane
      issue.apply_lane_timestamps!
      issue.save!
      issue.enqueue_velocity_recalculation!
      IssueAfterUpdateJob.perform_later(issue_id: issue.id, user_id: nil)
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
