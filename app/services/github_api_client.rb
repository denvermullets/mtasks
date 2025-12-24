class GithubApiClient
  class RateLimitError < StandardError; end
  class ApiError < StandardError; end

  def initialize(github_integration)
    @integration = github_integration
    @client = Octokit::Client.new(access_token: @integration.access_token)
  end

  def create_webhook
    webhook_url = Rails.application.routes.url_helpers.webhooks_github_url(
      host: ENV.fetch('APP_HOST', 'localhost:3000'),
      protocol: Rails.env.production? ? 'https' : 'http'
    )

    events = %w[pull_request]
    config = {
      url: webhook_url,
      content_type: 'json',
      secret: ENV.fetch('GITHUB_WEBHOOK_SECRET'),
      insecure_ssl: Rails.env.development? ? '1' : '0'
    }

    response = @client.create_hook(
      repo_full_name,
      'web',
      config,
      events: events,
      active: true
    )

    Rails.logger.info("Created GitHub webhook for #{repo_full_name}: #{response.id}")
    response
  rescue Octokit::Error => e
    handle_octokit_error(e)
  end

  def post_pr_comment(pr_number, comment_body)
    response = @client.add_comment(
      repo_full_name,
      pr_number,
      comment_body
    )

    Rails.logger.info("Posted comment to PR ##{pr_number} in #{repo_full_name}")
    response
  rescue Octokit::Error => e
    handle_octokit_error(e)
  end

  def repository
    @repository ||= @client.repository(repo_full_name)
  rescue Octokit::Error => e
    handle_octokit_error(e)
  end

  def rate_limit
    @client.rate_limit
  rescue Octokit::Error => e
    handle_octokit_error(e)
  end

  private

  def repo_full_name
    @integration.github_repo_full_name
  end

  def handle_octokit_error(error)
    case error
    when Octokit::TooManyRequests
      raise RateLimitError, "GitHub API rate limit exceeded: #{error.message}"
    when Octokit::Unauthorized, Octokit::Forbidden
      raise ApiError, "GitHub API authentication failed: #{error.message}"
    when Octokit::NotFound
      raise ApiError, "GitHub resource not found: #{error.message}"
    else
      raise ApiError, "GitHub API error: #{error.message}"
    end
  end
end
