require 'test_helper'

module Hourglass
  class PublicUrlTest < ActiveSupport::TestCase
    def with_env(value)
      original = ENV.fetch('MTASKS_PUBLIC_URL', nil)
      ENV['MTASKS_PUBLIC_URL'] = value
      yield
    ensure
      ENV['MTASKS_PUBLIC_URL'] = original
    end

    test 'reads MTASKS_PUBLIC_URL when set' do
      with_env('https://jait.example.com') do
        assert_equal 'https://jait.example.com', Hourglass::PublicUrl.base
      end
    end

    test 'strips a trailing slash from MTASKS_PUBLIC_URL' do
      with_env('https://jait.example.com/') do
        assert_equal 'https://jait.example.com', Hourglass::PublicUrl.base
      end
    end

    test 'falls back to default_url_options when env var blank' do
      with_env(nil) do
        # Test env default_url_options is { host: 'example.com' }
        assert_equal 'http://example.com', Hourglass::PublicUrl.base
      end
    end

    test 'falls back includes port when default_url_options sets one' do
      with_env(nil) do
        original = Rails.application.config.action_mailer.default_url_options
        Rails.application.config.action_mailer.default_url_options = { host: 'localhost', port: 3005 }
        assert_equal 'http://localhost:3005', Hourglass::PublicUrl.base
      ensure
        Rails.application.config.action_mailer.default_url_options = original
      end
    end
  end
end
