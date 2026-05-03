require 'test_helper'

module Discussion
  class ChatMessageFormatterTest < ActiveSupport::TestCase
    setup do
      @author = User.create!(name: 'Casey Smith', email: 'casey@example.com', password: 'password')
      @workspace = Workspace.create!(name: 'WS', owner: @author)
      @team = @workspace.teams.create!(name: 'T', identifier: 'CMF')
      @team.team_memberships.create!(user: @author)
      @project = @team.projects.create!(name: 'Proj')
    end

    test 'prefixes the author name and includes the body verbatim' do
      comment = @project.comments.create!(user: @author, body: '**hello** with [link](https://x.test)')
      result = ChatMessageFormatter.call(comment: comment)
      assert_equal 'Casey Smith said in JAIT: **hello** with [link](https://x.test)', result
    end

    test 'rewrites @Name mention to @email when target user has a hourglass user map' do
      target = User.create!(name: 'Robin Doe', email: 'robin@example.com', password: 'password')
      @team.team_memberships.create!(user: target)
      HourglassUserMap.create!(mtasks_user: target, hourglass_user_id: 'hu_robin', email: 'robin@example.com',
                               last_synced_at: Time.current)

      comment = @project.comments.create!(user: @author, body: 'hey @Robin Doe ping')
      result = ChatMessageFormatter.call(comment: comment)
      assert_equal 'Casey Smith said in JAIT: hey @robin@example.com ping', result
    end

    test 'leaves @Name alone when no hourglass user map exists' do
      target = User.create!(name: 'Robin Doe', email: 'robin@example.com', password: 'password')
      @team.team_memberships.create!(user: target)

      comment = @project.comments.create!(user: @author, body: 'hi @Robin Doe')
      result = ChatMessageFormatter.call(comment: comment)
      assert_equal 'Casey Smith said in JAIT: hi @Robin Doe', result
    end
  end
end
