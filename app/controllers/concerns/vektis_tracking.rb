# The controller-side seam for VEKTIS analytics (VEK-584).
#
# Taxonomy §9 puts server emission here rather than in model callbacks on purpose: Issue's
# lifecycle methods are also driven by Api::V1::IssuesController, which is not a catalogued
# surface, and a model callback could not tell the two apart. ApplicationController's concerns
# never reach ActionController::API, so including this here scopes emission to the web by
# construction.
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
  # Returns nil so it can never be spliced into control flow.
  def track_feature(feature_id, action, **properties)
    Vektis::EventEmitter.feature(feature_id, action, properties: properties.compact)
    nil
  end

  # Integration features (VEK-585) are the one place a server event carries `via`. The rest of the
  # catalog omits it because the server cannot see input modality — but `github-integration`/`link`
  # genuinely arrives from a web form, a webhook and a job, and the server can tell those apart
  # exactly. "Absence means web" would be a worse contract than saying so.
  def track_integration(feature_id, action, provider:, **properties)
    track_feature(feature_id, action, provider: provider, via: 'web', **properties)
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
