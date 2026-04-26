module ProjectsHelper
  HEALTH_MAP = {
    'completed' => %w[text-green-400 Complete],
    'cancelled' => %w[text-gray-500 Cancelled],
    'paused' => %w[text-orange-400 Paused]
  }.freeze

  def render_project_health(project)
    health_tag(*project_health_state(project))
  end

  def project_health_state(project)
    status = project.status&.to_s
    return HEALTH_MAP[status] if HEALTH_MAP.key?(status)
    return started_project_health_state(project) if status == 'started'
    return %w[text-red-400 Overdue] if project.due_date && project.due_date < Date.current

    ['text-gray-500', 'No updates']
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

  def started_project_health_state(project)
    return %w[text-green-400 Complete] if project.progress_percentage >= 100
    return ['text-red-400', 'At risk'] if project.behind_schedule?

    duration = project.start_date ? distance_of_time_in_words(project.start_date, Date.current) : nil
    label = duration ? "On track · #{compact_duration(duration)}" : 'On track'
    ['text-green-400', label]
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
