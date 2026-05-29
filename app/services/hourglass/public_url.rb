module Hourglass
  # Returns the canonical public URL for THIS mtasks instance, used when emitting
  # outbound notifications to Hourglass so links point back at the right host.
  # Set MTASKS_PUBLIC_URL in each environment (e.g. http://localhost:3005 in dev,
  # https://jait.production.com in prod). Falls back to action_mailer's
  # default_url_options if the env var isn't set.
  module PublicUrl
    module_function

    def base
      explicit = ENV['MTASKS_PUBLIC_URL'].to_s.strip
      return explicit.chomp('/') if explicit.present?

      from_default_url_options.chomp('/')
    end

    def from_default_url_options
      opts = Rails.application.config.action_mailer.default_url_options || {}
      protocol = opts[:protocol] || 'http'
      host = opts[:host]
      port = opts[:port]
      return '' if host.blank?

      port_segment = port.present? ? ":#{port}" : ''
      "#{protocol}://#{host}#{port_segment}"
    end
  end
end
