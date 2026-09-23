require 'test_helper'

class HourglassWebhookProcessorJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: 'Job User',
                         email: "jobuser_#{SecureRandom.hex(4)}@example.com",
                         password: 'password')
    @workspace = Workspace.create!(name: 'Job WS', owner: @user)
    @integration = @workspace.hourglass_integrations.create!(
      hourglass_server_id: "srv_#{SecureRandom.hex(4)}",
      base_url: 'https://hg.test',
      webhook_secret: 'secret',
      active: true
    )
    @delivery = WebhookDelivery.create!(
      source: 'hourglass',
      delivery_id: "del_#{SecureRandom.hex(4)}",
      event_type: 'message.created',
      received_at: Time.current,
      payload: { 'version' => 1, 'message_id' => 'm1' }
    )
  end

  test 'sets processed_at on the delivery' do
    HourglassWebhookProcessorJob.perform_now(@integration.id, @delivery.id)
    assert_not_nil @delivery.reload.processed_at
  end

  test 'noop when delivery already processed' do
    @delivery.update!(processed_at: 1.hour.ago)
    original = @delivery.processed_at.to_i
    HourglassWebhookProcessorJob.perform_now(@integration.id, @delivery.id)
    assert_equal original, @delivery.reload.processed_at.to_i
  end

  test 'tolerates unknown event types' do
    @delivery.update!(event_type: 'unknown.thing')
    assert_nothing_raised do
      HourglassWebhookProcessorJob.perform_now(@integration.id, @delivery.id)
    end
    assert_not_nil @delivery.reload.processed_at
  end

  test 'returns gracefully when integration missing' do
    assert_nothing_raised do
      HourglassWebhookProcessorJob.perform_now(999_999, @delivery.id)
    end
    assert_nil @delivery.reload.processed_at
  end

  DEFAULT_HANDLERS = {
    'message.created' => HourglassWebhookProcessor::Message::CreatedHandler,
    'message.updated' => HourglassWebhookProcessor::Message::UpdatedHandler,
    'message.deleted' => HourglassWebhookProcessor::Message::DeletedHandler,
    'message.pinned' => HourglassWebhookProcessor::Message::PinnedHandler,
    'message.unpinned' => HourglassWebhookProcessor::Message::UnpinnedHandler
  }.freeze

  def with_handlers(table)
    Kernel.silence_warnings { HourglassWebhookProcessorJob.const_set(:MESSAGE_HANDLERS, table) }
    yield
  ensure
    Kernel.silence_warnings { HourglassWebhookProcessorJob.const_set(:MESSAGE_HANDLERS, DEFAULT_HANDLERS) }
  end

  def with_link_handlers(table)
    original = HourglassWebhookProcessorJob::LINK_HANDLERS
    Kernel.silence_warnings { HourglassWebhookProcessorJob.const_set(:LINK_HANDLERS, table) }
    yield
  ensure
    Kernel.silence_warnings { HourglassWebhookProcessorJob.const_set(:LINK_HANDLERS, original) }
  end

  # Handlers are instantiated by the job — it needs the instance to read #tracked_team off it, so
  # a class-level .call double would never be reached. This mirrors BaseHandler's real protocol:
  # new(delivery, integration), then #call, then #tracked_team.
  def capturing_handler(captured, &capture)
    Class.new do
      define_method(:initialize) do |delivery, integration|
        @delivery = delivery
        @integration = integration
      end
      define_method(:call) { captured << capture.call(@delivery, @integration) }
      define_method(:tracked_team) { nil }
    end
  end

  test 'message.created routes to CreatedHandler' do
    captured = []
    handler = capturing_handler(captured) { |delivery, integration| [delivery.id, integration.id] }

    with_handlers('message.created' => handler) do
      HourglassWebhookProcessorJob.perform_now(@integration.id, @delivery.id)
    end

    assert_equal [[@delivery.id, @integration.id]], captured
  end

  test 'message.pinned routes to PinnedHandler' do
    captured = []
    handler = capturing_handler(captured) { |delivery, _integration| delivery.event_type }

    @delivery.update!(event_type: 'message.pinned')
    with_handlers('message.pinned' => handler) do
      HourglassWebhookProcessorJob.perform_now(@integration.id, @delivery.id)
    end

    assert_equal ['message.pinned'], captured
  end

  test 'message.unpinned routes to UnpinnedHandler' do
    captured = []
    handler = capturing_handler(captured) { |delivery, _integration| delivery.event_type }

    @delivery.update!(event_type: 'message.unpinned')
    with_handlers('message.unpinned' => handler) do
      HourglassWebhookProcessorJob.perform_now(@integration.id, @delivery.id)
    end

    assert_equal ['message.unpinned'], captured
  end

  test 'link.created routes to Link::CreatedHandler' do
    captured = []
    handler = capturing_handler(captured) { |delivery, _integration| delivery.event_type }

    @delivery.update!(event_type: 'link.created')
    with_link_handlers('link.created' => handler) do
      HourglassWebhookProcessorJob.perform_now(@integration.id, @delivery.id)
    end

    assert_equal ['link.created'], captured
  end

  test 'link.removed routes to Link::RemovedHandler' do
    captured = []
    handler = capturing_handler(captured) { |delivery, _integration| delivery.event_type }

    @delivery.update!(event_type: 'link.removed')
    with_link_handlers('link.removed' => handler) do
      HourglassWebhookProcessorJob.perform_now(@integration.id, @delivery.id)
    end

    assert_equal ['link.removed'], captured
  end

  test 'still marks processed when handler raises' do
    raising = Class.new do
      define_method(:initialize) { |_delivery, _integration| nil }
      define_method(:call) { raise 'kaboom' }
      define_method(:tracked_team) { nil }
    end

    with_handlers('message.created' => raising) do
      HourglassWebhookProcessorJob.perform_now(@integration.id, @delivery.id)
    end

    assert_not_nil @delivery.reload.processed_at
  end
end
