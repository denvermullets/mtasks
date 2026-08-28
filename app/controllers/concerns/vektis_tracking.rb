# The web seam for VEKTIS analytics (VEK-584).
#
# Taxonomy §9 puts server emission here rather than in model callbacks on purpose: Issue's
# lifecycle methods are also driven by Api::V1::IssuesController, and a model callback could not
# tell the two apart — it would emit one indistinguishable event for a click and for an agent.
# ApplicationController's concerns never reach ActionController::API, so including this here
# scopes emission to the web by construction, which is what makes `source: "server"` truthful.
#
# The API is a catalogued surface too now; VektisApiTracking is its seam and stamps `source:
# "api"`. The two files share the feature_id/action vocabulary and Vektis::IssueProperties, and
# nothing else — a gesture must be named identically on both, or analysis splits one feature in
# two. Anything that belongs to both belongs in app/services/vektis, not copied between them.
#
# Emission is an explicit line in each success branch rather than an after_action. Three call
# sites need state that only exists before the write (issue label_ids before assign_attributes,
# a lane's position before the reorder, a comment's depth before destroy) and two need values
# that exist only mid-action (the dependency bulk count, the exporter's row count) — none of
# which a response-time hook can recover. A greppable track_feature line is also the review
# artifact that keeps taxonomy drift visible.
module VektisTracking
  extend ActiveSupport::Concern

  private

  # Vektis::EventEmitter already stamps source/customer_id/user_id/event_id/timestamp, defers the
  # enqueue to after-commit, and swallows everything. Nothing more belongs here — in particular
  # not `via`, which the browser uses for input modality (web vs keyboard) and the server cannot
  # observe: the board `s` shortcut and a mouse click produce byte-identical PATCHes.
  #
  # The team is the VEKTIS tenant, and this is the seam that supplies it — which is why almost no
  # call site passes one. `current_team` is set for every authenticated request by TeamScoped and
  # is the right team on every team-scoped route; a controller where it is not overrides
  # `tracked_team`, and a single call site with a better answer passes `team:` directly.
  #
  # `team:` is a named parameter rather than a property so it can never be mistaken for one: the
  # closed registry would silently strip an unregistered `team` key and the event would go out
  # attributed to the wrong tenant.
  #
  # Returns nil so it can never be spliced into control flow.
  def track_feature(feature_id, action, team: tracked_team, **properties)
    Vektis::EventEmitter.feature(feature_id, action, team: team, properties: properties.compact)
    nil
  end

  # The tenant every event from this controller is attributed to. Nil means "emit nothing", which
  # the emitter handles — a workspace-scoped controller has no single team and guessing one would
  # file another tenant's activity under it.
  def tracked_team
    current_team
  end

  # Integration features (VEK-585) are the one place a server event carries `via`. The rest of the
  # catalog omits it because the server cannot see input modality — but `hourglass-integration`/
  # `link` genuinely arrives from a web form, a webhook and a job, and the server can tell those
  # apart exactly. "Absence means web" would be a worse contract than saying so.
  def track_integration(feature_id, action, provider:, team: tracked_team, **properties)
    track_feature(feature_id, action, team: team, provider: provider, via: 'web', **properties)
  end

  # Shared with the job paths VEK-585 instruments, which describe the same issues with no request
  # around them.
  def issue_shape(issue)
    Vektis::IssueProperties.shape(issue)
  end

  # `file_field multiple: true` posts a leading "" alongside the uploads, so counting the raw
  # array inflates every attachment event by one.
  def uploaded_file_count(files)
    Array(files).count { |file| file.respond_to?(:original_filename) }
  end
end
