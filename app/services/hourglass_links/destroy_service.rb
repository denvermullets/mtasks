module HourglassLinks
  class DestroyService < Service
    Result = Struct.new(:error, keyword_init: true)

    def initialize(link:)
      @link = link
    end

    def call
      payload = {
        integration_id: @link.hourglass_integration_id,
        channel_id: @link.hourglass_channel_id,
        project_id: @link.mtasks_project_id
      }

      @link.destroy!
      HourglassNotifyLinkDestroyedJob.perform_later(payload)
      Result.new(error: nil)
    rescue ActiveRecord::RecordNotDestroyed => e
      Result.new(error: e.message)
    end
  end
end
