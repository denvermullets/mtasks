class DashboardGroup < ApplicationRecord
  # Swatches offered in the group form. The column default comes first so a new group and
  # rows created before the palette existed always have a checked swatch.
  COLORS = %w[#6366f1 #ec4899 #3b82f6 #10b981 #f59e0b #ef4444 #8b5cf6 #14b8a6 #737373].freeze
  DIRECTIONS = %w[up down].freeze

  # Associations
  belongs_to :dashboard
  has_many :sources, class_name: 'DashboardGroupSource', dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :color, format: { with: /\A#\h{6}\z/ }

  def team_ids
    source_ids_for('Team')
  end

  def project_ids
    source_ids_for('Project')
  end

  # Sources that show every issue rather than only the ones assigned to the viewer.
  def all_team_ids
    source_ids_for('Team', include_all: true)
  end

  def all_project_ids
    source_ids_for('Project', include_all: true)
  end

  # Reads the loaded association when it's preloaded (the dashboard page does), otherwise queries.
  # `include_all: true` narrows to the sources flagged to show every issue.
  def source_ids_for(type, include_all: nil)
    if sources.loaded?
      sources.select { |source| source.source_type == type && (include_all.nil? || source.include_all == include_all) }
             .map(&:source_id)
    else
      scope = sources.where(source_type: type)
      scope = scope.where(include_all: include_all) unless include_all.nil?
      scope.pluck(:source_id)
    end
  end

  # Makes the group's sources exactly the given ids. `all_*_ids` flag which of them show every
  # issue (the rest are "assigned to me"); ids there that aren't also sources are ignored.
  # Callers own the access checks; this trusts what it's given.
  def replace_sources!(team_ids:, project_ids:, all_team_ids: [], all_project_ids: [])
    transaction do
      sync_sources('Team', team_ids, all_team_ids)
      sync_sources('Project', project_ids, all_project_ids)
    end
    sources.reset
    self
  end

  # Swaps places with the neighbour in `direction` and renumbers the dashboard's groups 1..n,
  # so rows with duplicate or zero positions heal themselves. A no-op at either edge.
  def move!(direction)
    offset = direction == 'up' ? -1 : 1

    dashboard.with_lock do
      siblings = dashboard.groups.reload.to_a
      index = siblings.index { |group| group.id == id }
      target = index + offset

      if target.between?(0, siblings.size - 1)
        siblings[index], siblings[target] = siblings[target], siblings[index]
        renumber(siblings)
      end
    end

    self
  end

  private

  def sync_sources(type, ids, all_ids)
    # `where.not(source_id: [])` compiles to NOT (1=0), i.e. every row, which is what
    # "keep none" means here. Don't "fix" it.
    sources.where(source_type: type).where.not(source_id: ids).delete_all
    ids.each do |id|
      source = sources.find_or_initialize_by(source_type: type, source_id: id)
      source.include_all = all_ids.include?(id)
      source.save! if source.changed?
    end
  end

  def renumber(groups)
    groups.each.with_index(1) do |group, pos|
      group.update_column(:position, pos) unless group.position == pos
    end
  end
end
