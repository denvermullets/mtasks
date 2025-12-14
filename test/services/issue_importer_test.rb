require 'test_helper'

# rubocop:disable Metrics/ClassLength
class IssueImporterTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test User', email: 'test@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'Test Workspace', owner: @user)
  end

  test 'creates team from CSV team column' do
    csv_data = <<~CSV
      Team,Title,Status
      Engineering,Test Issue,Backlog
    CSV

    importer = IssueImporter.new(@workspace, @user)
    result = importer.import(csv_data)

    assert result[:success]
    assert_equal 1, result[:imported]

    team = @workspace.teams.find_by(identifier: 'ENG')
    assert_not_nil team
    assert_equal 'Engineering', team.name
  end

  test 'generates identifier from team name letters only' do
    csv_data = <<~CSV
      Team,Title,Status
      99 Staples,Test Issue,Backlog
    CSV

    importer = IssueImporter.new(@workspace, @user)
    result = importer.import(csv_data)

    assert result[:success]

    team = @workspace.teams.find_by(identifier: 'STA')
    assert_not_nil team
    assert_equal '99 Staples', team.name
  end

  test 'pads short team names with X' do
    csv_data = <<~CSV
      Team,Title,Status
      AI,Test Issue,Backlog
    CSV

    importer = IssueImporter.new(@workspace, @user)
    result = importer.import(csv_data)

    assert result[:success]

    team = @workspace.teams.find_by(identifier: 'AIX')
    assert_not_nil team
    assert_equal 'AI', team.name
  end

  test 'creates team membership for importing user' do
    csv_data = <<~CSV
      Team,Title,Status
      Design,Test Issue,Backlog
    CSV

    importer = IssueImporter.new(@workspace, @user)
    importer.import(csv_data)

    team = @workspace.teams.find_by(identifier: 'DES')
    assert team.users.include?(@user)
  end

  test 'reuses existing team if identifier matches' do
    existing_team = @workspace.teams.create!(name: 'Engineering', identifier: 'ENG')

    csv_data = <<~CSV
      Team,Title,Status
      Engineering,Test Issue,Backlog
    CSV

    importer = IssueImporter.new(@workspace, @user)
    importer.import(csv_data)

    assert_equal 1, @workspace.teams.count
    assert_equal existing_team, @workspace.teams.first
  end

  test 'creates default team when no team column provided' do
    csv_data = <<~CSV
      Title,Status
      Test Issue,Backlog
    CSV

    importer = IssueImporter.new(@workspace, @user)
    result = importer.import(csv_data)

    assert result[:success]

    team = @workspace.teams.find_by(identifier: 'DEF')
    assert_not_nil team
    assert_equal 'Default', team.name
  end

  test 'imports issue with all attributes' do
    csv_data = <<~CSV
      Team,Title,Description,Status,Priority,Estimate
      ENG,Test Issue,Test description,In Progress,high,5
    CSV

    importer = IssueImporter.new(@workspace, @user)
    result = importer.import(csv_data)

    assert result[:success]
    assert_equal 1, result[:imported]

    issue = Issue.last
    assert_equal 'Test Issue', issue.title
    assert_equal 'Test description', issue.description
    assert_equal 'high', issue.priority
    assert_equal 5, issue.estimate
  end

  test 'creates lanes for each team' do
    csv_data = <<~CSV
      Team,Title,Status
      ENG,Issue 1,Todo
      DES,Issue 2,In Review
    CSV

    importer = IssueImporter.new(@workspace, @user)
    importer.import(csv_data)

    eng_team = @workspace.teams.find_by(identifier: 'ENG')
    des_team = @workspace.teams.find_by(identifier: 'DES')

    assert eng_team.lanes.find_by(name: 'Todo')
    assert des_team.lanes.find_by(name: 'In Review')
  end

  test 'handles multiple issues for same team' do
    csv_data = <<~CSV
      Team,Title,Status
      ENG,Issue 1,Backlog
      ENG,Issue 2,In Progress
      ENG,Issue 3,Done
    CSV

    importer = IssueImporter.new(@workspace, @user)
    result = importer.import(csv_data)

    assert result[:success]
    assert_equal 3, result[:imported]

    team = @workspace.teams.find_by(identifier: 'ENG')
    assert_equal 3, team.issues.count
  end
end
# rubocop:enable Metrics/ClassLength
