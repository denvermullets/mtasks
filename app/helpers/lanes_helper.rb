module LanesHelper
  LANE_CATEGORY_LABELS = {
    'backlog' => 'Backlog',
    'unstarted' => 'Unstarted',
    'started' => 'Started',
    'completed' => 'Completed',
    'canceled' => 'Canceled'
  }.freeze

  def lane_category_options
    LANE_CATEGORY_LABELS.map { |value, label| [label, value] }
  end
end
