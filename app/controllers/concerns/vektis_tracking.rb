# The web seam for VEKTIS analytics — mtasks' half of Vektis::Tracking.
#
# The gem supplies track_feature / track_integration and the fail-safe emit path. What stays here is
# what only mtasks knows: that its tenant is a Team, and that `team:` is the word its ~40 call sites
# use. Keeping the parameter name means the call sites read the same as they always did.
#
# Taxonomy §9 puts server emission in controllers rather than model callbacks on purpose: Issue's
# lifecycle methods are also driven by Api::V1::IssuesController, and a model callback could not
# tell the two apart — it would emit one indistinguishable event for a click and for an agent.
# ApplicationController's concerns never reach ActionController::API, so including this here scopes
# emission to the web by construction, which is what makes `source: "server"` truthful.
#
# The API is a catalogued surface too; VektisApiTracking is its seam and stamps `source: "api"`.
# The two files share the feature_id/action vocabulary and IssueTrackingProperties, and nothing
# else — a gesture must be named identically on both, or analysis splits one feature in two.
#
# Emission is an explicit line in each success branch rather than an after_action. Three call sites
# need state that only exists before the write (issue label_ids before assign_attributes, a lane's
# position before the reorder, a comment's depth before destroy) and two need values that exist only
# mid-action (the dependency bulk count, the exporter's row count) — none of which a response-time
# hook can recover. A greppable track_feature line is also the review artifact that keeps taxonomy
# drift visible.
module VektisTracking
  extend ActiveSupport::Concern
  include Vektis::Tracking

  private

  # `team:` rather than the gem's `tenant:`. The tenant IS the team here, and renaming it at 40 call
  # sites would be churn with no reader benefit.
  #
  # `current_team` is set for every authenticated request by TeamScoped and is the right team on
  # every team-scoped route; a controller where it is not overrides `tracked_team`, and a single
  # call site with a better answer passes `team:` directly.
  def track_feature(feature_id, action, team: tracked_team, **properties)
    super(feature_id, action, tenant: team, **properties)
  end

  def track_integration(feature_id, action, provider:, team: tracked_team, **properties)
    super(feature_id, action, provider: provider, tenant: team, **properties)
  end

  def tracked_team
    current_team
  end

  # The gem asks for the tenant under its own name; mtasks answers with the team.
  def tracked_tenant
    tracked_team
  end

  # Shared with the job paths, which describe the same issues with no request around them.
  def issue_shape(issue)
    IssueTrackingProperties.shape(issue)
  end

  # `file_field multiple: true` posts a leading "" alongside the uploads, so counting the raw array
  # inflates every attachment event by one.
  def uploaded_file_count(files)
    Array(files).count { |file| file.respond_to?(:original_filename) }
  end
end
