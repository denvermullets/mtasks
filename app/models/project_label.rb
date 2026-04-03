class ProjectLabel < ApplicationRecord
  belongs_to :project
  belongs_to :label
end
