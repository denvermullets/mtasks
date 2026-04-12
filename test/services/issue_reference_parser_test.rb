require 'test_helper'

class IssueReferenceParserTest < ActiveSupport::TestCase
  test 'parses 3-letter shortcodes from text' do
    result = IssueReferenceParser.parse('fix bug ABC-123')
    assert_equal ['ABC-123'], result
  end

  test 'parses 4-letter shortcodes from text' do
    result = IssueReferenceParser.parse('feat(channels): add rooms, HOUR-4')
    assert_equal ['HOUR-4'], result
  end

  test 'parses multiple shortcodes' do
    result = IssueReferenceParser.parse('fixes ABC-1 and HOUR-42')
    assert_includes result, 'ABC-1'
    assert_includes result, 'HOUR-42'
    assert_equal 2, result.length
  end

  test 'deduplicates shortcodes' do
    result = IssueReferenceParser.parse('ABC-1 and ABC-1 again')
    assert_equal ['ABC-1'], result
  end

  test 'returns empty array for blank text' do
    assert_equal [], IssueReferenceParser.parse(nil)
    assert_equal [], IssueReferenceParser.parse('')
  end

  test 'does not match 2-letter prefixes' do
    result = IssueReferenceParser.parse('AB-1')
    assert_equal [], result
  end

  test 'does not match 5-letter prefixes' do
    result = IssueReferenceParser.parse('ABCDE-1')
    assert_equal [], result
  end

  test 'matches lowercase prefixes' do
    result = IssueReferenceParser.parse('abc-1')
    assert_equal ['abc-1'], result
  end

  test 'matches mixed case prefixes' do
    result = IssueReferenceParser.parse('Jait-456')
    assert_equal ['Jait-456'], result
  end

  test 'extracts shortcodes from branch-name-like strings' do
    result = IssueReferenceParser.parse('feature/jait-123-fix-bug')
    assert_equal ['jait-123'], result
  end

  test 'parses shortcodes with digits in prefix' do
    result = IssueReferenceParser.parse('see 99S-2 for details')
    assert_equal ['99S-2'], result
  end

  test 'find_issues returns matching issues for a team' do
    user = User.create!(name: 'Test User', email: 'parser_test@example.com', password: 'password')
    workspace = Workspace.create!(name: 'Test Workspace', owner: user)
    team = Team.create!(name: 'Hourglass', identifier: 'HOUR', workspace: workspace)
    lane = Lane.create!(name: 'Backlog', team: team, position: 0)
    issue = Issue.create!(title: 'Test Issue', team: team, lane: lane, creator: user, team_number: 4)

    result = IssueReferenceParser.find_issues('fixes HOUR-4', team)

    assert_equal [issue], result
  end

  test 'find_issues resolves lowercase shortcodes' do
    user = User.create!(name: 'Test User', email: 'parser_lower@example.com', password: 'password')
    workspace = Workspace.create!(name: 'Test Workspace', owner: user)
    team = Team.create!(name: 'Hourglass', identifier: 'HOUR', workspace: workspace)
    lane = Lane.create!(name: 'Backlog', team: team, position: 0)
    issue = Issue.create!(title: 'Test Issue', team: team, lane: lane, creator: user, team_number: 4)

    result = IssueReferenceParser.find_issues('fixes hour-4', team)

    assert_equal [issue], result
  end

  test 'find_issues ignores shortcodes from other teams' do
    user = User.create!(name: 'Test User', email: 'parser_test2@example.com', password: 'password')
    workspace = Workspace.create!(name: 'Test Workspace', owner: user)
    team = Team.create!(name: 'Hourglass', identifier: 'HOUR', workspace: workspace)

    result = IssueReferenceParser.find_issues('fixes ABC-1', team)

    assert_equal [], result
  end
end
