module IssueDependencies
  # Removes a dependency. Both linked issues are touched explicitly so the removal shows up in
  # the next `updated_since` pull (no callbacks).
  class Unlink < Service
    def initialize(dependency:)
      @dependency = dependency
    end

    def call
      issues = [@dependency.blocking_issue, @dependency.blocked_issue]
      @dependency.destroy
      issues.each(&:touch) if @dependency.destroyed?
      @dependency
    end
  end
end
