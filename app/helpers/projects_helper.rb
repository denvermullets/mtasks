module ProjectsHelper
  HEALTH_MAP = {
    'completed' => %w[text-green-400 Complete],
    'cancelled' => %w[text-gray-500 Cancelled],
    'paused' => %w[text-orange-400 Paused]
  }.freeze

  def render_project_health(project)
    status = project.status&.to_s
    if HEALTH_MAP.key?(status)
      health_tag(*HEALTH_MAP[status])
    elsif status == 'started'
      started_health(project)
    else
      health_tag('text-gray-500', 'No updates')
    end
  end

  def render_progress_status(project)
    pct = project.progress_percentage
    color = progress_color(pct)
    icon = pct >= 100 ? render_project_status_icon('completed') : circle_icon(color)

    content_tag(:span, class: 'inline-flex items-center gap-1') do
      icon + content_tag(:span, "#{pct}%", class: "text-sm #{color}")
    end
  end

  private

  def started_health(project)
    return health_tag('text-red-400', 'At risk') if project.behind_schedule?

    duration = project.start_date ? distance_of_time_in_words(project.start_date, Date.current) : nil
    label = duration ? "On track · #{compact_duration(duration)}" : 'On track'
    health_tag('text-green-400', label)
  end

  def health_tag(color_class, label)
    content_tag(:span, class: "inline-flex items-center gap-1.5 text-sm #{color_class}") do
      content_tag(:span, '', class: 'w-2 h-2 rounded-full bg-current opacity-70') +
        content_tag(:span, label)
    end
  end

  def compact_duration(words)
    words.gsub('about ', '')
         .gsub('less than a minute', '<1m')
         .gsub(/(\d+) months?/, '\1mo')
         .gsub(/(\d+) days?/, '\1d')
         .gsub(/(\d+) years?/, '\1y')
         .gsub(/(\d+) hours?/, '\1h')
         .gsub(/(\d+) minutes?/, '\1m')
  end

  def progress_color(pct)
    if pct >= 100
      'text-green-400'
    elsif pct.positive?
      'text-yellow-400'
    else
      'text-gray-500'
    end
  end
end
