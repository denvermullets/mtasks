module GhIntegration
  class FindFromWebhook < Service
    # extra_text carries any text outside the PR itself that can reference an issue - currently a
    # PR comment body, which is the only way to attach an issue to a PR that never mentioned one.
    def initialize(installation_id:, repo_full_name:, pr_data:, extra_text: '')
      @installation_id = installation_id
      @repo_full_name = repo_full_name
      @pr_data = pr_data
      @extra_text = extra_text
    end

    def call
      subscriptions = find_all_subscriptions
      return [] if subscriptions.empty?

      team_identifiers = extract_team_identifiers_from_pr
      return [] if team_identifiers.empty?

      filter_by_team_identifiers(subscriptions, team_identifiers)
    end

    private

    def find_all_subscriptions
      GithubRepositorySubscription
        .joins(:github_installation)
        .where(
          github_installations: { installation_id: @installation_id },
          github_repo_full_name: @repo_full_name,
          active: true
        )
        .tap do |result|
          if result.empty?
            Rails.logger.info(
              "No subscriptions found for installation: #{@installation_id}, repo: #{@repo_full_name}"
            )
          end
        end
    end

    def extract_team_identifiers_from_pr
      branch_name = @pr_data.dig('head', 'ref') || ''
      pr_text = "#{@pr_data['title']} #{@pr_data['body']} #{branch_name} #{@extra_text}"
      shortcodes = IssueReferenceParser.parse(pr_text)

      if shortcodes.empty?
        Rails.logger.info("No issue shortcodes found in PR ##{@pr_data['number']}")
        return []
      end

      shortcodes.map { |sc| sc.split('-').first.upcase }.uniq
    end

    def filter_by_team_identifiers(subscriptions, team_identifiers)
      subscriptions
        .joins(:team)
        .where(teams: { identifier: team_identifiers })
        .tap do |result|
          Rails.logger.info(
            "Found #{result.count} matching subscription(s) for PR ##{@pr_data['number']} " \
            "(teams: #{team_identifiers.join(', ')})"
          )
        end
    end
  end
end
