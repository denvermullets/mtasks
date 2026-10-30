class Dashboard < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :groups, -> { order(:position, :id) }, class_name: 'DashboardGroup', dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 80 }

  # Scopes
  scope :ordered, -> { order(:position, :id) }

  # Puts the groups in the order of `ids` (from drag-and-drop) and renumbers them 1..n. Unknown ids
  # are ignored; groups missing from `ids` (a stale page) keep their relative order at the end.
  def reorder_groups!(ids)
    ids = Array(ids).map(&:to_i)

    with_lock do
      siblings = groups.reload.to_a
      renumber_groups(siblings.sort_by.with_index { |group, i| [ids.index(group.id) || ids.size, i] })
      touch
    end

    self
  end

  # Writes positions 1..n in the given order, skipping rows that already match. Bumps updated_at on
  # the rows it renumbers (update_columns skips timestamps) so sync sees the new order.
  def renumber_groups(ordered)
    now = Time.current
    ordered.each.with_index(1) do |group, pos|
      group.update_columns(position: pos, updated_at: now) unless group.position == pos
    end
  end
end
