module TeamsHelper
  # Ordered { key => label } for the team settings side nav. The first entry is the default section.
  def team_settings_sections(team)
    sections = { 'general' => 'General', 'lanes' => 'Lanes' }
    sections['members'] = 'Members' if team_admin?(team)
    sections.merge('integrations' => 'Integrations', 'recurring' => 'Recurring Issues')
  end
end
