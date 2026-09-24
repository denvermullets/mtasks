require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'downcases and strips email' do
    user = User.new(email: ' DOWNCASED@EXAMPLE.COM ', name: 'Test User')
    assert_equal('downcased@example.com', user.email)
  end

  test 'time zone defaults to UTC and ignores unknown values' do
    user = User.new(settings: {})
    assert_equal 'UTC', user.time_zone

    user.settings = { 'time_zone' => 'Mars/Olympus' }
    assert_equal 'UTC', user.time_zone

    user.settings = { 'time_zone' => 'Eastern Time (US & Canada)' }
    assert_equal 'Eastern Time (US & Canada)', user.time_zone
  end
end
