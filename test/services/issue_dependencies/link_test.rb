require 'test_helper'

module IssueDependencies
  class LinkTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: 'Linker', email: 'linker@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'Link Workspace', owner: @user)
      @team = @workspace.teams.create!(name: 'Link Team', identifier: 'LNK')
      @lane = @team.lanes.create!(name: 'Backlog', position: 0)

      @issue = @team.issues.create!(title: 'Issue', lane: @lane, creator: @user)
      @target = @team.issues.create!(title: 'Target', lane: @lane, creator: @user)
    end

    {
      'blocking' => ['blocks', :issue, :target],
      'blocked_by' => ['blocks', :target, :issue],
      'relates' => ['relates', :issue, :target],
      'duplicates' => ['duplicates', :issue, :target],
      'duplicated_by' => ['duplicates', :target, :issue]
    }.each do |direction, (kind, source, target)|
      test "#{direction} creates a #{kind} link from #{source} to #{target}" do
        dep = Link.call(issue: @issue, target: @target, direction: direction)

        assert dep.persisted?
        assert_equal kind, dep.kind
        assert_equal instance_variable_get("@#{source}"), dep.blocking_issue
        assert_equal instance_variable_get("@#{target}"), dep.blocked_issue
      end
    end

    test 'unknown or missing direction defaults to blocking' do
      [nil, '', 'sideways'].each_with_index do |direction, i|
        other = @team.issues.create!(title: "Other #{i}", lane: @lane, creator: @user)
        dep = Link.call(issue: @issue, target: other, direction: direction)

        assert dep.blocks?
        assert_equal @issue, dep.blocking_issue
        assert_equal other, dep.blocked_issue
      end
    end

    test 'direction_for reports the direction relative to each side' do
      blocks = Link.call(issue: @issue, target: @target, direction: 'blocking')
      assert_equal 'blocking', Link.direction_for(blocks, @issue)
      assert_equal 'blocked_by', Link.direction_for(blocks, @target)
      blocks.destroy

      relates = Link.call(issue: @issue, target: @target, direction: 'relates')
      assert_equal 'relates', Link.direction_for(relates, @issue)
      assert_equal 'relates', Link.direction_for(relates, @target)
      relates.destroy

      dup = Link.call(issue: @issue, target: @target, direction: 'duplicates')
      assert_equal 'duplicates', Link.direction_for(dup, @issue)
      assert_equal 'duplicated_by', Link.direction_for(dup, @target)
    end

    test 'returns an unsaved record with errors on a cycle' do
      Link.call(issue: @issue, target: @target, direction: 'blocking')
      third = @team.issues.create!(title: 'Third', lane: @lane, creator: @user)
      Link.call(issue: @target, target: third, direction: 'blocking')

      dep = Link.call(issue: third, target: @issue, direction: 'blocking')

      assert_not dep.persisted?
      assert_includes dep.errors.full_messages, 'Would create a circular dependency'
    end
  end
end
