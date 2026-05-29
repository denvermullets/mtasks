require 'test_helper'

class WebhookDeliveryTest < ActiveSupport::TestCase
  test 'requires source, delivery_id, event_type, received_at' do
    d = WebhookDelivery.new
    assert_not d.valid?
    assert_includes d.errors[:source], 'is not included in the list'
    assert_includes d.errors[:delivery_id], "can't be blank"
    assert_includes d.errors[:event_type], "can't be blank"
    assert_includes d.errors[:received_at], "can't be blank"
  end

  test 'rejects unknown source' do
    d = WebhookDelivery.new(source: 'slack', delivery_id: 'd1', event_type: 'x', received_at: Time.current)
    assert_not d.valid?
  end

  test 'delivery_id unique within source' do
    WebhookDelivery.create!(source: 'hourglass', delivery_id: 'dup', event_type: 'message.created',
                            received_at: Time.current)
    dup = WebhookDelivery.new(source: 'hourglass', delivery_id: 'dup', event_type: 'message.created',
                              received_at: Time.current)
    assert_not dup.valid?
  end

  test 'same delivery_id allowed across sources' do
    WebhookDelivery.create!(source: 'hourglass', delivery_id: 'shared', event_type: 'm', received_at: Time.current)
    other = WebhookDelivery.create!(source: 'github', delivery_id: 'shared', event_type: 'pr',
                                    received_at: Time.current)
    assert other.persisted?
  end

  test 'unprocessed scope filters processed_at IS NULL' do
    pending  = WebhookDelivery.create!(source: 'hourglass', delivery_id: 'p',  event_type: 'm',
                                       received_at: Time.current)
    done     = WebhookDelivery.create!(source: 'hourglass', delivery_id: 'd',  event_type: 'm',
                                       received_at: Time.current, processed_at: Time.current)

    ids = WebhookDelivery.unprocessed.pluck(:id)
    assert_includes ids, pending.id
    assert_not_includes ids, done.id
  end
end
