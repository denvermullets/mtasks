module IssueReferenceHelper
  def linkify_issue_references(text, team)
    return '' if text.blank?

    issues_by_identifier = IssueReferenceParser.find_issues(text, team)
                                               .index_by(&:identifier)

    escaped = ERB::Util.html_escape(text).to_str

    escaped.gsub(IssueReferenceParser::ISSUE_REFERENCE_REGEX) do |match|
      issue = issues_by_identifier[match]
      if issue
        link_to(match, team_issue_path(team, issue),
                class: 'text-accent hover:underline font-mono text-sm',
                data: { turbo_frame: '_top' })
      else
        match
      end
    end.html_safe
  end

  def format_with_issue_links(text, team)
    return '' if text.blank?

    simple_format(linkify_issue_references(text, team))
  end
end
