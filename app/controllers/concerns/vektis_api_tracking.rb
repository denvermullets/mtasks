# The v1 API's seam for VEKTIS analytics — the sibling of VektisTracking, and the reason the
# comment at the top of that file no longer says the API is uninstrumented by construction.
#
# It is a second seam rather than a shared one because the two surfaces disagree about almost
# everything a seam encodes. VektisTracking is bound to ApplicationController and assumes a
# session, multipart uploads, preloaded form collections and `via: 'web'`; none of that exists on
# ActionController::API. What the surfaces DO share — the feature_id/action vocabulary and the
# issue property shape — already lives in Vektis::Taxonomy and Vektis::IssueProperties, so this
# file adds a surface, not a dialect: a `create_issue` MCP call and a click on the new-issue form
# emit the same `issue-create`/`create` pair and differ only in `source`.
#
# The MCP server is not a separate surface. mtasks-mcp funnels all 19 of its tools through one
# `apiRequest` helper against this same API with the same ApiToken bearer and no client
# identifier, so Api::V1::BaseController is the single chokepoint for 100% of both, and
# `source: "api"` is the honest label for both.
module VektisApiTracking
  extend ActiveSupport::Concern

  included do
    # Reads are the one place this concern uses a hook where VektisTracking insists on an explicit
    # line. That rule exists because five web call sites need state that only survives until the
    # write — a lane's old position, a comment's depth, label_ids before assign_attributes. A read
    # has no such state, and a hook is what makes coverage total: an endpoint added to this API
    # next month is tracked without anyone remembering to add a line. Writes below stay explicit.
    after_action :track_api_read, if: -> { request.get? && response.successful? }
  end

  private

  # Vektis::EventEmitter already stamps customer_id/user_id/event_id/timestamp, defers the enqueue
  # to after-commit, and swallows everything. `Current.user` is set by authenticate_api_token! on
  # every request here, so user_id needs no plumbing.
  #
  # `via` is deliberately absent, as it is on the web. It carries input modality, and a bearer
  # token says nothing about how the call was composed — an agent, a curl and a cron job produce
  # byte-identical requests.
  def track_api_feature(feature_id, action, team: tracked_team, **properties)
    Vektis::EventEmitter.feature(feature_id, action, team: team,
                                                     properties: properties.compact, source: 'api')
    nil
  end

  # The team is the VEKTIS tenant. `current_team` is the attr_reader BaseController already
  # exposes, set by each controller's `set_current_team` from a membership- and token-scope-checked
  # params[:team_id].
  #
  # Four endpoints never set one and correctly emit nothing: users#me and users#by_email are about
  # a person rather than a tenant, teams#index spans every team the token can see, and
  # integrations#handshake runs on a workspace-scoped bootstrap token. EventEmitter.emit returns
  # early on a blank team, so that is absence rather than a hole to paper over — guessing a tenant
  # would file one team's activity under another.
  def tracked_team
    current_team
  end

  def issue_shape(issue)
    Vektis::IssueProperties.shape(issue)
  end

  # One event per successful GET. `entity` comes from the route rather than the response so it
  # costs nothing and can never carry a record id or user text (§6); `result_count` is present
  # only where an action set it, which is exactly the collection endpoints — `properties.compact`
  # drops it for a `show` rather than shipping a meaningless 1.
  def track_api_read
    track_api_feature('api-read', 'query',
                      entity: controller_name.singularize,
                      result_count: @tracked_result_count)
  end
end
