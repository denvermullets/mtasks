class IssueReferenceParser
  ISSUE_REFERENCE_REGEX = /\b([A-Z]{3,4}-\d+)\b/

  def initialize(text)
    @text = text
  end

  def parse
    return [] if @text.blank?

    @text.scan(ISSUE_REFERENCE_REGEX).flatten.uniq
  end

  def find_issues(team)
    identifiers = parse
    return [] if identifiers.empty?

    identifiers.filter_map do |identifier|
      prefix, number = identifier.split('-')
      next unless prefix == team.identifier

      team.issues.find_by(team_number: number.to_i)
    end
  end

  def self.parse(text)
    new(text).parse
  end

  def self.find_issues(text, team)
    new(text).find_issues(team)
  end
end
