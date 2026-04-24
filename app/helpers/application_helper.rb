module ApplicationHelper
  def user_avatar(user, size: 'md', shape: 'circle', extra_classes: '')
    render partial: 'shared/user_avatar', locals: { user: user, size: size, shape: shape, extra_classes: extra_classes }
  end

  def format_target_date(date)
    return nil unless date

    formatted = "#{date.strftime('%b')} #{date.day.ordinalize}"
    formatted += ", #{date.year}" if date.year != Date.current.year
    formatted
  end

  # Returns { url:, label: } for a top-bar back link.
  # Prefers request.referer when it's a same-origin page other than the current one
  # and maps to a known destination. Falls back otherwise.
  def back_nav_link(fallback_url:, fallback_label:)
    ref = request.referer
    return { url: fallback_url, label: fallback_label } if ref.blank?

    uri = URI.parse(ref)
    same_origin = uri.host == request.host && uri.port == request.port
    return { url: fallback_url, label: fallback_label } unless same_origin
    return { url: fallback_url, label: fallback_label } if uri.path == request.path

    label = back_nav_label_for(uri.path)
    { url: ref, label: label || fallback_label }
  rescue URI::InvalidURIError
    { url: fallback_url, label: fallback_label }
  end

  BACK_NAV_RULES = [
    [%r{\A/teams/[^/]+/issues/(?<id>\d+)(?:/edit)?/?\z}, ->(m) { Issue.find_by(id: m[:id])&.identifier || 'Issue' }],
    [%r{\A/teams/[^/]+/projects/(?<id>\d+)(?:/edit)?/?\z}, ->(m) { Project.find_by(id: m[:id])&.name || 'Project' }],
    [%r{\A/teams/[^/]+/issues/?\z}, 'Issues'],
    [%r{\A/teams/[^/]+/projects(?:/new)?/?\z}, 'Projects'],
    [%r{\A/teams/[^/]+/roadmap/?\z}, 'Roadmap'],
    [%r{\A/teams/[^/]+/edit/?\z}, 'Team settings'],
    [%r{\A/settings/appearance/?\z}, 'Appearance'],
    [%r{\A/api-tokens/?\z}, 'API tokens']
  ].freeze

  def back_nav_label_for(path)
    BACK_NAV_RULES.each do |pattern, label|
      match = pattern.match(path)
      next unless match

      return label.respond_to?(:call) ? label.call(match) : label
    end
    nil
  end
end
