require 'test_helper'

module Vektis
  # VEK-587: the §5.2 closed property registry is the mechanical half of §6's PII ban — a free-text
  # field cannot reach the wire without being registered first. Both emit paths enforce it, so the
  # registry exists twice: Vektis::Taxonomy::PROPERTY_KEYS for the server, and a PROPERTY_KEYS Set
  # in app/javascript/vektis.js for the browser.
  #
  # There is no build step that could share one constant — importmap serves the JS from disk with no
  # compilation — so the copies are kept honest here instead. Drift is silent and one-directional in
  # the dangerous case: a key added to Ruby but not JS makes the browser drop data it should send,
  # while a key added to JS but not Ruby lets an unreviewed field through.
  class PropertyRegistryParityTest < ActiveSupport::TestCase
    WRAPPER = Rails.root.join('app/javascript/vektis.js')

    # Matches the `const PROPERTY_KEYS = new Set([...]);` literal and pulls out the quoted strings.
    def browser_property_keys
      source = WRAPPER.read
      literal = source[/const PROPERTY_KEYS = new Set\(\[(.*?)\]\);/m, 1]
      assert literal, 'could not find the PROPERTY_KEYS Set literal in app/javascript/vektis.js'

      literal.scan(/"([^"]+)"/).flatten
    end

    test 'the browser registry matches Vektis::Taxonomy::PROPERTY_KEYS exactly' do
      assert_equal Taxonomy::PROPERTY_KEYS.sort, browser_property_keys.sort,
                   'app/javascript/vektis.js and Vektis::Taxonomy::PROPERTY_KEYS have drifted — ' \
                   'edit both, and the taxonomy document, in the same change'
    end

    test 'the browser registry has no duplicates' do
      keys = browser_property_keys
      assert_equal keys.uniq, keys
    end

    test 'source is registered, since both paths stamp it on every event' do
      assert_includes Taxonomy::PROPERTY_KEYS, 'source'
      assert_includes browser_property_keys, 'source'
    end
  end
end
