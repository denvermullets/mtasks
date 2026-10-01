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
    end

    self
  end

  # Writes positions 1..n in the given order, skipping rows that already match.
  def renumber_groups(ordered)
    ordered.each.with_index(1) do |group, pos|
      group.update_column(:position, pos) unless group.position == pos
    end
  end
end
