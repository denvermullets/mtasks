require 'commonmarker'
require 'rouge'
require 'nokogiri'

class MarkdownRenderer
  COMMONMARKER_OPTIONS = {
    render: { unsafe: false, hardbreaks: false },
    extension: {
      table: true,
      strikethrough: true,
      tasklist: true,
      autolink: true,
      tagfilter: true
    }
  }.freeze

  COMMONMARKER_PLUGINS = { syntax_highlighter: nil }.freeze

  SKIP_ANCESTORS = %w[pre code a].freeze

  def self.render(text, team: nil)
    new(text, team: team).render
  end

  def initialize(text, team: nil)
    @text = text.to_s
    @team = team
  end

  def render
    return ''.html_safe if @text.blank?

    html = Commonmarker.to_html(@text, options: COMMONMARKER_OPTIONS, plugins: COMMONMARKER_PLUGINS)
    fragment = Nokogiri::HTML5.fragment(html)

    highlight_code_blocks(fragment)
    linkify_issue_refs(fragment) if @team
    linkify_user_mentions(fragment) if @team

    fragment.to_html.html_safe
  end

  private

  def highlight_code_blocks(fragment)
    fragment.css('pre > code').each do |code_node|
      pre_node = code_node.parent
      lang = pre_node['lang'] || code_node['class'].to_s[/language-(\S+)/, 1]
      lexer = (lang && Rouge::Lexer.find(lang)) || Rouge::Lexers::PlainText.new
      formatter = Rouge::Formatters::HTML.new
      highlighted = formatter.format(lexer.lex(code_node.text))
      code_node.inner_html = highlighted
      pre_node['class'] = [pre_node['class'], 'highlight'].compact.join(' ')
    end
  end

  def linkify_issue_refs(fragment)
    issues_by_identifier = IssueReferenceParser.find_issues(@text, @team).index_by(&:identifier)
    return if issues_by_identifier.empty?

    fragment.traverse do |node|
      next unless node.text?
      next if skip_node?(node)
      next unless node.content.match?(IssueReferenceParser::ISSUE_REFERENCE_REGEX)

      replacement = replace_refs(node.content, issues_by_identifier)
      node.replace(Nokogiri::HTML5.fragment(replacement))
    end
  end

  def linkify_user_mentions(fragment)
    members = @team.users.to_a
    return if members.empty?

    pattern = UserMentionParser.build_pattern(members)
    by_downcased = members.index_by { |u| u.name.downcase }

    fragment.traverse do |node|
      next unless node.text?
      next if skip_node?(node)
      next unless node.content.include?('@')
      next unless node.content.match?(pattern)

      replacement = replace_user_mentions(node.content, pattern, by_downcased)
      node.replace(Nokogiri::HTML5.fragment(replacement))
    end
  end

  def replace_user_mentions(text, pattern, by_downcased)
    result = +''
    last_index = 0
    text.scan(pattern) do
      md = Regexp.last_match
      result << CGI.escapeHTML(text[last_index...md.begin(0)])
      user = by_downcased[md[1].downcase]
      result << if user
                  %(<span class="mention text-accent font-medium">@#{CGI.escapeHTML(user.name)}</span>)
                else
                  CGI.escapeHTML(md[0])
                end
      last_index = md.end(0)
    end
    result << CGI.escapeHTML(text[last_index..])
    result
  end

  def skip_node?(node)
    node.ancestors.any? { |a| SKIP_ANCESTORS.include?(a.name) }
  end

  def replace_refs(text, issues_by_identifier)
    escaped = CGI.escapeHTML(text)
    escaped.gsub(IssueReferenceParser::ISSUE_REFERENCE_REGEX) do |match|
      issue = issues_by_identifier[match]
      next match unless issue

      path = Rails.application.routes.url_helpers.team_issue_path(@team, issue)
      %(<a href="#{path}" class="text-accent hover:underline font-mono text-sm" data-turbo-frame="_top">#{match}</a>)
    end
  end
end
