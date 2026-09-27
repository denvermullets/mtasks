# Upserts a PR from GitHub webhook data, links the issues it references, and applies the
# subscription's automation rule for the webhook action. Returns the PR, or nil if it failed to save.
class GithubPrSyncService < Service
  def initialize(subscription:, pr_data:, action: nil)
    @subscription = subscription
    @team = subscription.team
    @pr_data = pr_data
    @action = action
  end

  def call
    pull_request = find_or_initialize_pull_request
    pull_request.assign_attributes(build_pr_attributes)

    if pull_request.save
      Rails.logger.info("Synced PR ##{pull_request.pr_number} for team #{@team.identifier}")
      GhIntegration::LinkIssuesFromText.call(
        subscription: @subscription, pull_request: pull_request, text: issue_reference_text
      )
      apply_automation_rules(pull_request) if @action
      pull_request
    else
      Rails.logger.error("Failed to sync PR ##{@pr_data['number']}: #{pull_request.errors.full_messages.join(', ')}")
      nil
    end
  end

  private

  def issue_reference_text
    "#{@pr_data['title']} #{@pr_data['body']} #{@pr_data.dig('head', 'ref')}"
  end

  def find_or_initialize_pull_request
    @subscription.pull_requests.find_or_initialize_by(pr_number: @pr_data['number'])
  end

  def build_pr_attributes
    {
      title: @pr_data['title'],
      body: @pr_data['body'],
      html_url: @pr_data['html_url'],
      state: @pr_data['state'],
      author_login: @pr_data['user']['login'],
      head_ref: @pr_data['head']['ref'],
      base_ref: @pr_data['base']['ref'],
      merged: @pr_data['merged'] || false,
      merged_at: parse_github_time(@pr_data['merged_at']),
      closed_at: parse_github_time(@pr_data['closed_at']),
      github_created_at: parse_github_time(@pr_data['created_at']),
      github_updated_at: parse_github_time(@pr_data['updated_at'])
    }
  end

  def apply_automation_rules(pull_request)
    trigger = determine_trigger(pull_request)
    return unless trigger

    rules = @subscription.pr_automation_rules.where(trigger: trigger)

    rules = rules.select { |rule| File.fnmatch(rule.branch_pattern, pull_request.base_ref) } if trigger == 'pr_merged'

    return if rules.empty?

    rule = rules.first
    GhIntegration::MoveIssuesToLane.call(issues: pull_request.issues, lane: rule.lane)
  end

  def determine_trigger(pull_request)
    case @action
    when 'opened', 'reopened'
      'pr_opened'
    when 'closed'
      pull_request.merged? ? 'pr_merged' : 'pr_closed'
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
