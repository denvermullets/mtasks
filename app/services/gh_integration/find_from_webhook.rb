module GhIntegration
  class FindFromWebhook < Service
    def initialize(installation_id:, repo_full_name:, pr_data:)
      @installation_id = installation_id
      @repo_full_name = repo_full_name
      @pr_data = pr_data
    end

    def call
      # Step 1: Find all teams subscribed to this repo
      all_subscriptions = GithubRepositorySubscription
                          .joins(:github_installation)
                          .where(
                            github_installations: { installation_id: @installation_id },
                            github_repo_full_name: @repo_full_name,
                            active: true
                          )

      if all_subscriptions.empty?
        Rails.logger.info("No subscriptions found for installation: #{@installation_id}, repo: #{@repo_full_name}")
        return []
      end

      # Step 2: Parse PR title + body for shortcodes (e.g., "ENG-123", "MKT-456")
      pr_text = "#{@pr_data['title']} #{@pr_data['body']}"
      shortcodes = IssueReferenceParser.parse(pr_text)

      if shortcodes.empty?
        Rails.logger.info("No issue shortcodes found in PR ##{@pr_data['number']}")
        return []
      end

      # Step 3: Extract team identifiers from shortcodes
      team_identifiers = shortcodes.map { |sc| sc.split('-').first }.uniq

      # Step 4: Filter subscriptions to only teams mentioned
      matching_subscriptions = all_subscriptions
                               .joins(:team)
                               .where(teams: { identifier: team_identifiers })

      Rails.logger.info(
        "Found #{matching_subscriptions.count} matching subscription(s) for PR ##{@pr_data['number']} " \
        "(teams: #{team_identifiers.join(', ')})"
      )

      matching_subscriptions
    end
  end
end
