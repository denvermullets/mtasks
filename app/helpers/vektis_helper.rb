# Server-rendered handoff of Vektis analytics config to the browser SDK.
#
# Values are read from the Vektis config initializer only — nothing here touches
# ENV directly.
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
  PUBLISHABLE_KEY_PREFIX = 'vk_pub_'.freeze

  # Attributes for the <body> tag, or {} when analytics must not be exposed.
  def vektis_dataset_attributes
    return {} unless Vektis.enabled?
    return {} unless authenticated?
    return {} unless vektis_publishable_key?

    {
      'data-vektis-key-value' => Vektis.publishable_key,
      'data-vektis-endpoint-value' => Vektis.endpoint,
      'data-vektis-customer-id-value' => Vektis.customer_id,
      # Opaque numeric ID, never the email — identify() must not carry PII.
      'data-vektis-user-id-value' => current_user.id.to_s,
      'data-vektis-debug-value' => Rails.env.development?.to_s
    }
  end

  # The `vektis` token for the <body> data-controller list, gated on exactly the
  # same conditions as the attributes above. Stimulus reads `data-vektis-*-value`
  # only off the element carrying a matching `data-controller`, so the two must
  # appear together — and attaching the controller without them would leave a
  # no-op running on the landing page and every unauthenticated view.
  def vektis_controller_token
    vektis_dataset_attributes.any? ? ' vektis' : ''
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
  # initializes), so a misconfigured VEKTIS_PUBLISHABLE_KEY would leak silently.
  # Refuse to render instead.
  def vektis_publishable_key?
    return true if Vektis.publishable_key.to_s.start_with?(PUBLISHABLE_KEY_PREFIX)

    Rails.logger.error(
      '[Vektis] Refusing to render analytics attributes: VEKTIS_PUBLISHABLE_KEY is not a ' \
      "publishable (#{PUBLISHABLE_KEY_PREFIX}*) key. A full-scope key must never reach the browser."
    )
    false
  end
end
