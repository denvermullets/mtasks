module IconHelper
  def render_priority_icon(priority)
    case priority
    when 'urgent'  then svg_icon('text-red-400', 'M6 20V10M12 20V4M18 20V10', stroke_width: '2.5')
    when 'high'    then priority_split_icon('text-orange-400', 'M6 20V14M12 20V8', 'M18 20V14')
    when 'medium'  then priority_split_icon('text-yellow-400', 'M6 20V14', 'M12 20V14M18 20V14')
    when 'low'     then svg_icon('text-blue-400', 'M19 14l-7 7m0 0l-7-7m7 7V3')
    else                svg_icon('text-gray-500', 'M5 12h14')
    end
  end

  def render_lane_icon(lane)
    case lane&.name&.downcase
    when 'backlog'     then dashed_circle_icon('text-gray-500')
    when 'in progress' then half_circle_icon('text-yellow-400')
    when 'done'        then svg_icon('text-green-400', CHECKMARK_CIRCLE)
    when 'cancelled'   then svg_icon('text-gray-500', X_CIRCLE)
    else                    circle_icon('text-gray-500')
    end
  end

  def render_group_icon(group_object)
    case group_object
    when Lane      then render_lane_icon(group_object)
    when String    then render_priority_icon(group_object)
    when Project   then svg_icon('text-gray-500', PROJECT_PATH)
    when Milestone then svg_icon('text-gray-500', CHECKMARK_CIRCLE)
    when Label     then svg_icon('text-gray-500', LABEL_PATH)
    when User      then svg_icon('text-gray-500', USER_PATH)
    else content_tag(:div, class: 'w-4 h-4 rounded-full border border-gray-600') { '' }
    end
  end

  def render_project_status_icon(status)
    case status&.to_s
    when 'backlog'   then dashed_circle_icon('text-gray-500')
    when 'started'   then half_circle_icon('text-yellow-400')
    when 'paused'    then pause_circle_icon('text-orange-400')
    when 'completed' then svg_icon('text-green-400', CHECKMARK_CIRCLE)
    when 'cancelled' then svg_icon('text-gray-500', X_CIRCLE)
    else                  circle_icon('text-gray-500')
    end
  end

  CHECKMARK_CIRCLE = 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z'.freeze
  X_CIRCLE = 'M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z'.freeze
  PROJECT_PATH = 'M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4'.freeze
  USER_PATH = 'M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z'.freeze
  LABEL_PATH = 'M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 ' \
               '2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z'.freeze

  private

  def svg_icon(color_class, path_d, stroke_width: '2')
    content_tag(:svg, nil, class: "w-4 h-4 #{color_class}", fill: 'none',
                           stroke: 'currentColor', viewBox: '0 0 24 24') do
      content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-linejoin': 'round',
                              'stroke-width': stroke_width, d: path_d)
    end
  end

  def priority_split_icon(color_class, active_path, dim_path)
    content_tag(:svg, nil, class: "w-4 h-4 #{color_class}", fill: 'none',
                           stroke: 'currentColor', viewBox: '0 0 24 24') do
      content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-width': '2.5', d: active_path) +
        content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-width': '2.5',
                                d: dim_path, class: 'text-gray-600')
    end
  end

  def dashed_circle_icon(color_class)
    content_tag(:svg, nil, class: "w-4 h-4 #{color_class}", fill: 'none',
                           stroke: 'currentColor', viewBox: '0 0 24 24') do
      content_tag(:circle, nil, cx: '12', cy: '12', r: '9',
                                'stroke-width': '2', 'stroke-dasharray': '4 2')
    end
  end

  def half_circle_icon(color_class)
    content_tag(:svg, nil, class: "w-4 h-4 #{color_class}", viewBox: '0 0 24 24') do
      content_tag(:circle, nil, cx: '12', cy: '12', r: '9', fill: 'none',
                                stroke: 'currentColor', 'stroke-width': '2') +
        content_tag(:path, nil, d: 'M12 3a9 9 0 010 18V3z', fill: 'currentColor')
    end
  end

  def circle_icon(color_class)
    content_tag(:svg, nil, class: "w-4 h-4 #{color_class}", fill: 'none',
                           stroke: 'currentColor', viewBox: '0 0 24 24') do
      content_tag(:circle, nil, cx: '12', cy: '12', r: '9', 'stroke-width': '2')
    end
  end

  def pause_circle_icon(color_class)
    content_tag(:svg, nil, class: "w-4 h-4 #{color_class}", fill: 'none',
                           stroke: 'currentColor', viewBox: '0 0 24 24') do
      content_tag(:circle, nil, cx: '12', cy: '12', r: '9', 'stroke-width': '2') +
        content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-width': '2.5',
                                d: 'M10 9v6M14 9v6')
    end
  end
end
