class UserMentionParser
  def self.find_users(text, team)
    return [] if text.blank?

    members = team.users.to_a
    return [] if members.empty?

    pattern = build_pattern(members)
    names_found = text.scan(pattern).flatten.map(&:downcase).uniq
    return [] if names_found.empty?

    by_downcased = members.index_by { |u| u.name.downcase }
    names_found.filter_map { |n| by_downcased[n] }
  end

  # Name collisions within a team resolve to one user (index_by keeps the last match).
  def self.build_pattern(members)
    alternation = members.sort_by { |u| -u.name.length }
                         .map { |u| Regexp.escape(u.name) }
                         .join('|')
    /(?<!\w)@(#{alternation})(?!\w)/i
  end
end
