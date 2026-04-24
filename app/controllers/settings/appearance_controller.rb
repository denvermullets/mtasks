class Settings::AppearanceController < ApplicationController
  MONO_STACK_FALLBACK = 'ui-monospace, monospace'.freeze
  SANS_STACK_FALLBACK = 'ui-sans-serif, system-ui, sans-serif'.freeze

  FONT_OPTIONS = [
    { id: 'ibm-plex-mono', name: 'IBM Plex Mono', family: 'IBM Plex Mono', category: :mono },
    { id: 'jetbrains-mono', name: 'JetBrains Mono', family: 'JetBrains Mono', category: :mono },
    { id: 'fira-code', name: 'Fira Code', family: 'Fira Code', category: :mono },
    { id: 'suse-mono', name: 'SUSE Mono', family: 'SUSE Mono', category: :mono },
    { id: 'roboto-mono', name: 'Roboto Mono', family: 'Roboto Mono', category: :mono },
    { id: 'atkinson-hyperlegible-mono', name: 'Atkinson Hyperlegible Mono',
      family: 'Atkinson Hyperlegible Mono', category: :mono },
    { id: 'inter', name: 'Inter', family: 'Inter', category: :sans },
    { id: 'ibm-plex-sans', name: 'IBM Plex Sans', family: 'IBM Plex Sans', category: :sans },
    { id: 'space-grotesk', name: 'Space Grotesk', family: 'Space Grotesk', category: :sans },
    { id: 'system', name: 'System', family: nil, category: :sans }
  ].freeze
  private_constant :MONO_STACK_FALLBACK, :SANS_STACK_FALLBACK, :FONT_OPTIONS

  def show
    @themes = theme_swatches
    @fonts = font_options
  end

  def update
    theme = params[:theme]
    font = params[:font]

    unless User::AVAILABLE_THEMES.include?(theme)
      redirect_to settings_appearance_path, alert: 'Unknown theme.' and return
    end

    redirect_to settings_appearance_path, alert: 'Unknown font.' and return unless User::AVAILABLE_FONTS.include?(font)

    current_settings = current_user.settings || {}
    appearance = current_settings.fetch('appearance', {})
    appearance['theme'] = theme
    appearance['font'] = font
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

  def font_options
    FONT_OPTIONS.map do |opt|
      fallback = opt[:category] == :mono ? MONO_STACK_FALLBACK : SANS_STACK_FALLBACK
      stack = opt[:family] ? %("#{opt[:family]}", #{fallback}) : fallback
      { id: opt[:id], name: opt[:name], stack: stack }
    end
  end
end
