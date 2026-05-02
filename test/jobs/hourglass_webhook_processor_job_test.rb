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
end
