# Link kinds for the dependency map: blocks (directional), relates (symmetric), duplicates (source -> canonical target).
class AddKindToIssueDependencies < ActiveRecord::Migration[8.1]
  def change
    add_column :issue_dependencies, :kind, :string, null: false, default: 'blocks'
    add_index :issue_dependencies, :kind
  end
end
