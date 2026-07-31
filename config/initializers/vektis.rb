# Vektis Analytics Configuration
#
# The single configuration surface for VEKTIS analytics. Both the browser path
# (Stimulus controller + @vektis-io/tracker) and the server path (Vektis::ApiClient)
# read from here — nothing else should touch ENV for these values.
#
# All five settings are ENV-driven via dotenv. Analytics is DISABLED by default,
# so nothing emits in test or CI, and a missing key is never a boot failure.
# Every emit path must check `Vektis.enabled?` first.
module Vektis
  class << self
    # Master kill switch. Defaults to FALSE.
    # The trailing `|| false` is load-bearing: ActiveModel casts an empty string
    # to nil, and `VEKTIS_ENABLED=` in a .env file is an easy way to get one.
    # This reader must always return a real boolean — it is rendered to the browser.
    def enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('VEKTIS_ENABLED', false)) || false
    end

    # Defaults to LOCAL vanalytics, not production. The browser SDK's built-in
    # default is production, so the Stimulus controller must pass this value
    # explicitly — a missed override sends dogfood traffic to prod.
    def endpoint
      ENV.fetch('VEKTIS_ENDPOINT', 'http://localhost:3333/api/v1/events')
    end

    # Publishable key (vk_pub_*), browser-safe, rate tier 1,000 req/min.
    # Default is the vanalytics local seed value.
    def publishable_key
      ENV.fetch('VEKTIS_PUBLISHABLE_KEY', 'vk_pub_dev_local_playground')
    end

    # Full-scope key, rate tier 10,000 req/min. SERVER ONLY — never render this
    # to the browser. Default is the vanalytics local seed value.
    def server_key
      ENV.fetch('VEKTIS_SERVER_KEY', 'vk_dev_local_internal')
    end

    # A single constant for all of mtasks — mtasks is one VEKTIS tenant. It is
    # NOT derived from the Workspace/Team hierarchy. The real value is
    # provisioned by vektis-app; until then, a local placeholder.
    def customer_id
      ENV.fetch('VEKTIS_CUSTOMER_ID', 'mtasks-local-dev')
    end
  end
end
