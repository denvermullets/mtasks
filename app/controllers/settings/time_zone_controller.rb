# Per-user time zone preference, stored in users.settings alongside appearance. Used as the default
# zone for anything scheduled by calendar date, such as recurring issues.
class Settings::TimeZoneController < ApplicationController
  def show; end

  def update
    time_zone = params[:time_zone].to_s

    unless ActiveSupport::TimeZone[time_zone]
      redirect_to settings_time_zone_path, alert: 'Unknown time zone.', status: :see_other and return
    end

    current_user.update!(settings: (current_user.settings || {}).merge('time_zone' => time_zone))
    redirect_to settings_time_zone_path, notice: 'Time zone saved', status: :see_other
  end
end
