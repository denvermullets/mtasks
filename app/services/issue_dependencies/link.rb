module IssueDependencies
  # Links two issues. `direction` is always relative to `issue`: 'blocked_by' means the target
  # blocks `issue`, 'duplicated_by' means the target duplicates `issue`, and so on.
  class Link < Service
    # direction => [kind, whether `issue` is the source (blocking_issue) side]
    DIRECTIONS = {
      'blocking' => ['blocks', true],
      'blocked_by' => ['blocks', false],
      'relates' => ['relates', true],
      'duplicates' => ['duplicates', true],
      'duplicated_by' => ['duplicates', false]
    }.freeze
    DEFAULT_DIRECTION = 'blocking'.freeze

    # Unknown or missing directions mean 'blocking', matching the pre-kind behavior the
    # MCP tool relies on.
    def self.normalize_direction(direction)
      DIRECTIONS.key?(direction.to_s) ? direction.to_s : DEFAULT_DIRECTION
    end

    def self.direction_for(dependency, issue)
      source = dependency.blocking_issue_id == issue.id

      case dependency.kind
      when 'relates' then 'relates'
      when 'duplicates' then source ? 'duplicates' : 'duplicated_by'
      else source ? 'blocking' : 'blocked_by'
      end
    end

    def initialize(issue:, target:, direction:)
      @issue = issue
      @target = target
      @direction = self.class.normalize_direction(direction)
    end

    # Returns the dependency, saved or carrying validation errors.
    def call
      kind, issue_is_source = DIRECTIONS.fetch(@direction)
      source, target = issue_is_source ? [@issue, @target] : [@target, @issue]

      dependency = IssueDependency.new(kind: kind, blocking_issue: source, blocked_issue: target)
      dependency.save
      dependency
    end
  end
end
