module SettingsHelper
  # Ordered { key => label } for the user settings side nav. The first entry is the default section.
  def user_settings_sections
    sections = { 'appearance' => 'Appearance', 'home_page' => 'Home Page', 'team_order' => 'Team Order',
                 'time_zone' => 'Time Zone', 'api_tokens' => 'API Tokens' }
    sections['integrations'] = 'Integrations' if current_team&.workspace
    sections
  end
end
