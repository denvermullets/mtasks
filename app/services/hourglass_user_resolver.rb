class HourglassUserResolver < Service
  Result = Struct.new(:user, :display_name, :avatar_initials, :user_map, keyword_init: true)

  def initialize(email:, integration:, hourglass_user_id: nil, display_name: nil, lazy_fetch: false)
    @email = email.to_s.strip.presence
    @hourglass_user_id = hourglass_user_id.to_s.strip.presence
    @display_name = display_name
    @integration = integration
    @lazy_fetch = lazy_fetch
  end

  def call
    map = lookup_map
    return result(user: map.mtasks_user, user_map: map) if map
    return result if @email.blank? || !@lazy_fetch

    fetch_and_persist
  end

  private

  def lookup_map
    if @hourglass_user_id
      hit = HourglassUserMap.find_by(hourglass_user_id: @hourglass_user_id)
      return hit if hit
    end
    @email ? HourglassUserMap.find_by(email: @email) : nil
  end

  def fetch_and_persist
    payload = Hourglass::ApiClient.for_integration(@integration).identify_user(email: @email)
    hourglass_id = payload['id']&.to_s
    payload_display = payload['display_name'] || payload['name']
    user = local_user_for(@email)

    if user && hourglass_id
      map = persist_map(user, hourglass_id)
      result(user: user, user_map: map, override_display_name: payload_display)
    else
      result(override_display_name: payload_display)
    end
  rescue Hourglass::ApiClient::Error => e
    Rails.logger.warn("HourglassUserResolver lazy_fetch failed: #{e.message}")
    result
  end

  def persist_map(user, hourglass_id)
    HourglassUserMap.create!(
      mtasks_user: user,
      hourglass_user_id: hourglass_id,
      email: @email,
      last_synced_at: Time.current
    )
  end

  def local_user_for(email)
    User.where('LOWER(email) = ?', email.downcase).first
  end

  def result(user: nil, user_map: nil, override_display_name: nil)
    name = display_name_for(user, user_map, override_display_name)
    Result.new(user: user, user_map: user_map, display_name: name, avatar_initials: initials_for(name))
  end

  # rubocop:disable Metrics/CyclomaticComplexity
  def display_name_for(user, user_map, override)
    candidates = [
      override,
      @display_name,
      user_map&.mtasks_user&.name,
      user&.name,
      @email&.split('@')&.first
    ]
    candidates.find(&:present?) || 'Unknown'
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  def initials_for(name)
    parts = name.to_s.split(/\s+/).reject(&:blank?)
    return '?' if parts.empty?

    (parts.first[0].to_s + (parts.length > 1 ? parts.last[0].to_s : '')).upcase
  end
end
