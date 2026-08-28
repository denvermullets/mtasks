# A team's resolved VEKTIS configuration, read by both the browser handoff (VektisHelper) and the
# server path (EventEmitter, ApiClient, VektisEventJob). Nothing else should touch the record.
#
# Mirrors NullConfig's surface exactly, so no caller ever needs to know which one it holds.
module Vektis
  class Config
    attr_reader :record

    def initialize(record)
      @record = record
    end

    def enabled?
      record.enabled?
    end

    def publishable_key
      record.publishable_key
    end

    def server_key
      record.server_key
    end

    def customer_id
      record.customer_id
    end

    def endpoint
      Vektis.endpoint
    end
  end
end
