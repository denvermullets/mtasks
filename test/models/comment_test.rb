require "test_helper"

class CommentTest < ActiveSupport::TestCase
  test "should belong to issue" do
    comment = Comment.new
    assert_respond_to comment, :issue
  end

  test "should belong to user" do
    comment = Comment.new
    assert_respond_to comment, :user
  end

  test "should validate presence of body" do
    comment = Comment.new
    assert_not comment.valid?
    assert_includes comment.errors[:body], "can't be blank"
  end
end
