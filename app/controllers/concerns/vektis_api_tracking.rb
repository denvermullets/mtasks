# The v1 API's seam for VEKTIS analytics — mtasks' half of Vektis::ApiTracking.
#
# A second seam rather than a shared one because the two surfaces disagree about almost everything a
# seam encodes. VektisTracking is bound to ApplicationController and assumes a session, multipart
# uploads, preloaded form collections and `via: 'web'`; none of that exists on
# ActionController::API. What the surfaces DO share — the feature_id/action vocabulary and the issue
# property shape — lives in EventTaxonomy and IssueTrackingProperties, so this file adds a surface,
# not a dialect: a `create_issue` MCP call and a click on the new-issue form emit the same
# `issue-create`/`create` pair and differ only in `source`.
#
# The MCP server is not a separate surface. mtasks-mcp funnels all 19 of its tools through one
# `apiRequest` helper against this same API with the same ApiToken bearer and no client identifier,
# so Api::V1::BaseController is the single chokepoint for 100% of both, and `source: "api"` is the
# honest label for both.
#
# The gem contributes the after_action read hook and the emit path; what stays here is the team.
module VektisApiTracking
  extend ActiveSupport::Concern
  include Vektis::ApiTracking

  private

  # `team:` rather than the gem's `tenant:`, matching VektisTracking so the two surfaces read alike.
  def track_api_feature(feature_id, action, team: tracked_team, **properties)
    super(feature_id, action, tenant: team, **properties)
  end

  # `current_team` is the attr_reader BaseController already exposes, set by each controller's
  # `set_current_team` from a membership- and token-scope-checked params[:team_id].
  #
  # Four endpoints never set one and correctly emit nothing: users#me and users#by_email are about a
  # person rather than a tenant, teams#index spans every team the token can see, and
  # integrations#handshake runs on a workspace-scoped bootstrap token. The emitter returns early on
  # a blank tenant, so that is absence rather than a hole to paper over — guessing a tenant would
  # file one team's activity under another.
  def tracked_team
    current_team
  end

  def tracked_tenant
    tracked_team
  end

  def issue_shape(issue)
    IssueTrackingProperties.shape(issue)
  end
end
