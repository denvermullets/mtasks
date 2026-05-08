# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

return unless Rails.env.development?

# Create admin user
admin = User.find_or_create_by!(email: "admin@example.com") do |user|
  user.password = "password"
  user.password_confirmation = "password"
  user.name = "Admin User"
end

puts "Created admin user: #{admin.email}"

# Create workspace
workspace = Workspace.find_or_create_by!(name: "My Tasks") do |ws|
  ws.owner = admin
end

puts "Created workspace: #{workspace.name}"

# Create team (this will auto-create default lanes via callback)
team = Team.find_or_create_by!(name: "Engineering", workspace: workspace) do |t|
  t.identifier = "MTK"
end

puts "Created team: #{team.name} with #{team.lanes.count} lanes"

# Add admin to team
TeamMembership.find_or_create_by!(user: admin, team: team) do |tm|
  tm.role = :admin
end

# Create a project
project = Project.find_or_create_by!(name: "User Authentication") do |p|
  p.team = team
  p.description = "Implement user authentication system"
end

puts "Created project: #{project.name}"

# Create some labels
labels = []
["Bug", "Feature", "Enhancement"].each do |label_name|
  label = Label.find_or_create_by!(name: label_name, team: team) do |l|
    l.color = case label_name
    when "Bug" then "#ef4444"
    when "Feature" then "#3b82f6"
    when "Enhancement" then "#8b5cf6"
    end
  end
  labels << label
end

puts "Created #{labels.count} labels"

# Create sample issues
backlog_lane = team.lanes.find_by(name: "Backlog")
in_progress_lane = team.lanes.find_by(name: "In Progress")
done_lane = team.lanes.find_by(name: "Done")

issues_data = [
  { title: "Set up authentication system", lane: done_lane, priority: :high, project: project, status: :completed },
  { title: "Add password reset functionality", lane: in_progress_lane, priority: :high, project: project },
  { title: "Implement session management", lane: backlog_lane, priority: :medium, project: project },
  { title: "Add email verification", lane: backlog_lane, priority: :low, project: project },
  { title: "Fix login redirect bug", lane: done_lane, priority: :urgent, status: :completed }
]

issues_data.each_with_index do |issue_data, index|
  next if Issue.exists?(title: issue_data[:title], team: team)

  issue = Issue.create!(
    title: issue_data[:title],
    description: "Description for #{issue_data[:title]}",
    team: team,
    lane: issue_data[:lane],
    priority: issue_data[:priority],
    project: issue_data[:project],
    creator: admin,
    assignee: index.even? ? admin : nil
  )

  issue.complete! if issue_data[:status] == :completed
  issue.start! if issue_data[:lane] == in_progress_lane

  issue.labels << labels.sample
  puts "Created issue: #{issue.identifier} - #{issue.title}"
end

puts "\nSeed data created successfully!"
puts "Login with: admin@example.com / password"
