class HourglassOutboundEmitterJob < ApplicationJob
  queue_as :default

  retry_on Hourglass::ApiClient::Error, wait: :exponentially_longer, attempts: 3

  def self.dispatch_create(issue, actor)
    perform_later(event_type: 'issue.created', issue_id: issue.id, actor_id: actor.id)
  end

  def perform(event_type:, issue_id:, actor_id:, version_id: nil)
    @event_type = event_type
    @version_id = version_id
    return unless prepare?(issue_id, actor_id)

    dispatch
  rescue Hourglass::ApiClient::Unauthorized => e
    Rails.logger.warn("HourglassOutboundEmitterJob marking link #{@link&.id} broken: #{e.message}")
    @link&.update(status: 'broken')
  rescue Hourglass::ApiClient::NotFound => e
    Rails.logger.warn("HourglassOutboundEmitterJob #{event_type} issue=#{issue_id}: not found (#{e.message}); skipping")
  end

  private

  def prepare?(issue_id, actor_id)
    @issue = Issue.find_by(id: issue_id)
    @actor = User.find_by(id: actor_id)
    return false unless @issue && @actor

    @link = resolve_link
    return false if @link.nil? || @link.broken?

    @version = @version_id ? PaperTrail::Version.find_by(id: @version_id) : nil
    true
  end

  def dispatch
    body = Hourglass::OutboundMessageComposer.call(
      event_type: @event_type, issue: @issue, actor: @actor, version: @version
    )
    response = post_message(body)
    record_echo(response, body)
  end

  def resolve_link
    thread = HourglassLink.issue_thread.where(mtasks_issue_id: @issue.id).active.first
    return thread if thread && @event_type != 'issue.created'
    return nil unless @issue.project

    HourglassLink.for_project(@issue.project).active.first
  end

  def post_message(body)
    client = Hourglass::ApiClient.for_integration(@link.hourglass_integration)
    key = "issue-#{@issue.id}-#{@event_type}-#{@version_id || 'create'}"

    if @link.link_type == 'issue_thread'
      client.post_thread_message(@link.hourglass_thread_id, body: body, message_type: 'system', idempotency_key: key)
    else
      client.post_channel_message(@link.hourglass_channel_id, body: body, message_type: 'system', idempotency_key: key)
    end
  end

  def record_echo(response, body)
    return unless response.is_a?(Hash)

    message_id = response['id']&.to_s
    channel_id = response['channel_id']&.to_s.presence || channel_id_from_link
    return if message_id.blank? || channel_id.blank?

    HourglassMessageCache.create!(echo_attributes(message_id, channel_id, body))
  end

  def echo_attributes(message_id, channel_id, body)
    {
      hourglass_message_id: message_id,
      hourglass_channel_id: channel_id,
      hourglass_thread_id: @link.hourglass_thread_id,
      body: body,
      message_type: 'system',
      posted_at: Time.current,
      source: 'echo',
      payload: { event_type: @event_type, issue_id: @issue.id, version_id: @version_id }
    }
  end

  def channel_id_from_link
    return @link.hourglass_channel_id if @link.hourglass_channel_id.present?
    return nil if @link.hourglass_thread_id.blank?

    HourglassMessageCache.where(hourglass_message_id: @link.hourglass_thread_id).pick(:hourglass_channel_id)
  end
end
