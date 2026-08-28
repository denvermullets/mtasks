# Server-rendered handoff of Vektis analytics config to the browser SDK.
#
# Values come from the current team's TeamVektisIntegration — each team is its own VEKTIS tenant,
# so which key the page carries depends on which team the viewer is looking at.
#
# Rendered onto <body>, not <html>, because these use Stimulus value naming and
# Stimulus only reads `data-<identifier>-<name>-value` off the element that
# carries the matching `data-controller`.
#
# The Stimulus naming is load-bearing, not just idiomatic. @vektis-io/tracker
# runs tryAutoInit() at module evaluation; under importmap there is no
# `document.currentScript`, so it falls back to scanning for a literal
# `data-vektis-key` attribute and warns VEK_TRK_AUTOINIT_UNAVAILABLE when it
# finds one it cannot act on. That warning is not gated by the SDK's `debug`
# flag, so the SDK's own documented attribute names would log a spurious warning
# on every page load — including production — even though the Stimulus
# controller initializes the SDK correctly a moment later. The `-value` suffix
# keeps that scan from matching.
module VektisHelper
  # Attributes for the <body> tag, or {} when analytics must not be exposed.
  def vektis_dataset_attributes
    return {} unless authenticated?

    config = Vektis.for(current_team)
    return {} unless config.enabled?
    return {} unless vektis_publishable_key?(config)

    {
      'data-vektis-key-value' => config.publishable_key,
      'data-vektis-endpoint-value' => config.endpoint,
      'data-vektis-customer-id-value' => config.customer_id,
      # Opaque numeric ID, never the email — identify() must not carry PII.
      'data-vektis-user-id-value' => current_user.id.to_s,
      'data-vektis-debug-value' => Rails.env.development?.to_s
    }
  end

  # The `vektis` token for the <body> data-controller list. Attached on every authenticated page,
  # including pages for a team with no analytics — which is deliberate, and not the same rule the
  # attributes follow.
  #
  # The SDK is a module singleton and Turbo swaps <body> without a page load, so its identity
  # outlives navigation. If this token were gated on credentials the way the attributes are, then
  # switching from a connected team to an unconnected one would simply detach this controller,
  # leaving the previous team's key and customer_id live in the SDK while every sibling controller
  # kept calling track(). The unconnected team's activity would be billed to the connected team's
  # VEKTIS account. This controller is the only thing that can call reset(), so it has to be
  # present on the page where the tearing-down needs to happen.
  #
  # Unauthenticated views still get nothing: there are no call sites there, and a sign-out lands on
  # a page with no team to reconcile against.
  def vektis_controller_token
    authenticated? ? ' vektis' : ''
  end

  # Render-ready form for interpolation directly into the <body> tag. Returns a
  # leading-space-prefixed attribute string, or empty when there is nothing to
  # render, so the tag never picks up a stray trailing space.
  def vektis_body_attributes
    attributes = vektis_dataset_attributes
    return ''.html_safe if attributes.empty?

    ' '.html_safe + tag.attributes(attributes)
  end

  private

  # The full-scope server key must never reach the browser. The SDK only *warns*
  # on a non-publishable key (and with the default allowFullScopeKey it still
  # initializes), so a misconfigured key would leak silently. Refuse to render
  # instead. TeamVektisIntegration validates the same prefix on save; this is the
  # backstop for a row written before that validation, or around it.
  def vektis_publishable_key?(config)
    prefix = TeamVektisIntegration::PUBLISHABLE_KEY_PREFIX
    return true if config.publishable_key.to_s.start_with?(prefix)

    Rails.logger.error(
      "[Vektis] Refusing to render analytics attributes for team #{current_team&.id}: the " \
      "publishable key is not a publishable (#{prefix}*) key. A full-scope key must never reach " \
      'the browser.'
    )
    false
  end
end
