# The "analytics is off for this team" config: no record, or a record with tracking disabled.
#
# A null object rather than nil because analytics must never be the thing that raises. Every
# consumer can call the same readers unconditionally and gate on `enabled?`.
module Vektis
  class NullConfig
    def enabled?
      false
    end

    def publishable_key
      nil
    end

    def server_key
      nil
    end

    def customer_id
      nil
    end

    def endpoint
      Vektis.endpoint
    end
  end
end
