class IssueReferenceService < Service
  def initialize(source_issue:, text:, source_type:, user:)
    @source_issue = source_issue
    @text = text
    @source_type = source_type
    @user = user
  end

  def call
    referenced_issues = IssueReferenceParser.find_issues(@text, @source_issue.team)
    referenced_issues.each do |referenced_issue|
      next if referenced_issue.id == @source_issue.id

      IssueReference.find_or_create_by(
        source_issue: @source_issue,
        referenced_issue: referenced_issue,
        source_type: @source_type
      ) do |ref|
        ref.user = @user
      end
    end
  end
end
