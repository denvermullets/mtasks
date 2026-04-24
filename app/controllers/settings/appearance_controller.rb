class Settings::AppearanceController < ApplicationController
  def show
    @themes = theme_swatches
  end

  def update
    theme = params[:theme]
    unless User::AVAILABLE_THEMES.include?(theme)
      redirect_to settings_appearance_path, alert: 'Unknown theme.' and return
    end

    current_settings = current_user.settings || {}
    appearance = current_settings.fetch('appearance', {})
    appearance['theme'] = theme
    current_user.update!(settings: current_settings.merge('appearance' => appearance))

    redirect_to settings_appearance_path, notice: 'Appearance updated.', status: :see_other
  end

  private

  def theme_swatches
    [
      { id: 'default',             name: 'Default',             colors: %w[#92E8D4 #0B0A0A #22242B] },
      { id: 'warm-paper',          name: 'Warm Paper',          colors: %w[#da5f1c #f4f0e8 #c9bca8] },
      { id: 'cool-linen',          name: 'Cool Linen',          colors: %w[#1a8aaa #f0f2f5 #b8bfc9] },
      { id: 'phosphor-amber',      name: 'Phosphor Amber',      colors: %w[#e8a820 #0e0c08 #3a2a10] },
      { id: 'phosphor-green',      name: 'Phosphor Green',      colors: %w[#7ae890 #080e08 #1e4a22] },
      { id: 'dusk',                name: 'Dusk',                colors: %w[#f07a70 #16121e #4a4060] },
      { id: 'brutalist-newsprint', name: 'Brutalist Newsprint', colors: %w[#e8d820 #181610 #3a3830] },
      { id: 'muted-sage',          name: 'Muted Sage',          colors: %w[#60d890 #283430 #4a6054] },
      { id: 'deep-navy',           name: 'Deep Navy',           colors: %w[#f08030 #101828 #2a3a52] },
      { id: 'warm-dusk',           name: 'Warm Dusk',           colors: %w[#50e8c0 #22141c #3a2430] },
      { id: 'ink',                 name: 'Ink',                 colors: %w[#aaee44 #141414 #444444] },
      { id: 'ocean-floor',         name: 'Ocean Floor',         colors: %w[#d4a84a #0e1820 #2a4258] },
      { id: 'ash',                 name: 'Ash',                 colors: %w[#ff5a3c #282828 #484848] },
      { id: 'chalk',               name: 'Chalk',               colors: %w[#0a6870 #f5f4f0 #d0cec8] },
      { id: 'dusk-redux',          name: 'Dusk Redux',          colors: %w[#f0a070 #181424 #3a3060] }
    ]
  end
end
