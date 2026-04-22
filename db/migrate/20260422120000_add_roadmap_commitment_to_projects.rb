class AddRoadmapCommitmentToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :roadmap_commitment, :string
    add_index :projects, %i[team_id roadmap_commitment]
  end
end
