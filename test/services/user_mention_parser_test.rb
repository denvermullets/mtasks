require 'test_helper'

class UserMentionParserTest < ActiveSupport::TestCase
  setup do
    owner = User.create!(name: 'Owner', email: 'ump_owner@example.com', password: 'password')
    @workspace = Workspace.create!(name: 'UMP Workspace', owner: owner)
    @team = Team.create!(name: 'Alpha', identifier: 'ALPH', workspace: @workspace)
    @jane = create_member('Jane Doe', 'ump_jane@example.com')
    @jane_single = create_member('Jane', 'ump_jane2@example.com')
    @bob = create_member('Bob Smith', 'ump_bob@example.com')
  end

  test 'returns empty for blank text' do
    assert_equal [], UserMentionParser.find_users(nil, @team)
    assert_equal [], UserMentionParser.find_users('', @team)
  end

  test 'finds a simple mention' do
    result = UserMentionParser.find_users('Hi @Bob Smith, thoughts?', @team)
    assert_equal [@bob], result
  end

  test 'prefers longest name match' do
    result = UserMentionParser.find_users('ping @Jane Doe please', @team)
    assert_equal [@jane], result
    refute_includes result, @jane_single
  end

  test 'matches single name when no longer match applies' do
    result = UserMentionParser.find_users('ping @Jane please', @team)
    assert_equal [@jane_single], result
  end

  test 'is case-insensitive' do
    result = UserMentionParser.find_users('@jane doe wake up', @team)
    assert_equal [@jane], result
  end

  test 'ignores non-members' do
    result = UserMentionParser.find_users('hello @Nobody Nope', @team)
    assert_equal [], result
  end

  test 'does not match when @ is preceded by a word char' do
    result = UserMentionParser.find_users('email bob@Bob Smith.com', @team)
    assert_equal [], result
  end

  test 'deduplicates mentions of the same user' do
    result = UserMentionParser.find_users('@Bob Smith and @Bob Smith again', @team)
    assert_equal [@bob], result
  end

  private

  def create_member(name, email)
    user = User.create!(name: name, email: email, password: 'password')
    TeamMembership.create!(user: user, team: @team)
    user
  end
end
