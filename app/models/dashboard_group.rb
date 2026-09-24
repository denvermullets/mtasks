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

  # Reads the loaded association when it's preloaded (the dashboard page does), otherwise queries.
  def source_ids_for(type)
    if sources.loaded?
      sources.select { |source| source.source_type == type }.map(&:source_id)
    else
      sources.where(source_type: type).pluck(:source_id)
    end
  end

  # Makes the group's sources exactly the given ids. Callers own the access checks; this
  # trusts what it's given.
  def replace_sources!(team_ids:, project_ids:)
    transaction do
      # `where.not(source_id: [])` compiles to NOT (1=0), i.e. every row, which is what
      # "keep none" means here. Don't "fix" it.
      sources.where(source_type: 'Team').where.not(source_id: team_ids).delete_all
      sources.where(source_type: 'Project').where.not(source_id: project_ids).delete_all
      team_ids.each { |id| sources.find_or_create_by!(source_type: 'Team', source_id: id) }
      project_ids.each { |id| sources.find_or_create_by!(source_type: 'Project', source_id: id) }
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

  def renumber(groups)
    groups.each.with_index(1) do |group, pos|
      group.update_column(:position, pos) unless group.position == pos
    end
  end
end
