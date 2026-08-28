# The Ruby transcription of .notes/mtasks-event-taxonomy.md (VEK-573), which is authoritative.
#
# Kept apart from Vektis::EventEmitter because it is data, not behavior: this is the registry the
# emitter validates against, the list VEK-584 and VEK-585 write call sites from, and the thing
# VEK-586 asserts the payload contract against. Editing any constant here means editing the
# taxonomy document in the same change — a slug is a permanent join key (§2), so the document is
# the source of truth and this file follows it, never the reverse.
module Vektis
  module Taxonomy
    # §1 — the five types in @vektis-io/events-schema@1.1.0. Frozen contract; no new types.
    EVENT_TYPES = %w[feature.used feature.engagement feature.first_use
                     session.active customer.identified].freeze
    FEATURE_TYPES = %w[feature.used feature.engagement feature.first_use].freeze

    # Server-owned (feature_id => actions) pairs, from §4 and §9. The ownership rule is per-pair,
    # not per-feature: exactly one side emits any given (feature_id, action). Browser-owned slugs
    # (issue-search, issue-filter, keyboard-shortcut, notification-drawer) are absent by design —
    # emitting one from the server would double-count a gesture the browser already reported. The
    # three split features appear with their server halves only; the browser keeps `view`.
    CATALOG = {
      'issue-create' => %w[create],
      'issue-edit' => %w[update],
      'issue-delete' => %w[delete],
      'issue-workflow' => %w[move complete cancel reopen archive],
      'issue-dependency' => %w[link unlink],
      'sub-issue' => %w[link unlink],
      'issue-label' => %w[apply remove],
      'issue-transfer' => %w[move],
      'issue-attachment' => %w[create remove],
      'project-management' => %w[create update delete],
      'project-label' => %w[apply remove],
      'label-management' => %w[create update delete],
      'lane-management' => %w[create update delete],
      'roadmap' => %w[create],
      'comment' => %w[create delete],
      'decision' => %w[create delete],
      'notification' => %w[read read_all],
      'github-integration' => %w[link unlink sync complete],
      'hourglass-integration' => %w[link unlink sync],
      'csv-import' => %w[import],
      'team-export' => %w[export]
    }.freeze

    # §5.2 — the closed property registry. Adding a key is an edit to the taxonomy document, not a
    # call-site decision, and that is also what keeps §6's PII ban mechanical: a free-text field
    # cannot reach the wire without being registered here first.
    PROPERTY_KEYS = %w[source via surface entity provider webhook_event from_position to_position
                       direction priority count depth filter_type option tab shortcut query_length
                       result_count has_project has_assignee has_estimate has_due_date
                       is_sub_issue].freeze

    # §8 — the fixed namespace for the deterministic UUIDv5 event_ids that integration-originated
    # events carry (VEK-585). A permanent join key in the same sense a slug is: changing it would
    # re-key every event mtasks has ever sent from a webhook, so it is a literal, never generated.
    EVENT_ID_NAMESPACE = '35c2de9f-8af2-4dd9-bf80-e1a6cf5d12d3'.freeze

    # §1 — schema caps. Breaching one is a 400, and a 400 drops the whole batch with no retry.
    MAX_FIELD_LENGTH = 255
    MAX_PROPERTY_KEYS = 50
    MAX_PROPERTY_KEY_LENGTH = 64
    MAX_STRING_VALUE_LENGTH = 1024
    MAX_EVENT_BYTES = 8_192
  end
end
