import { getStatus, track } from "@vektis-io/tracker";

// The single seam between mtasks' Stimulus controllers and @vektis-io/tracker. No controller other
// than vektis_controller.js, which bootstraps the SDK, imports the SDK directly.
//
// Three jobs, none of which belongs in a call site:
//
// 1. properties.source = "browser" is mandatory on every event (taxonomy §5.1) and is the only
//    field that makes browser and server events separable in analysis. Stamping it here is what
//    makes "no exceptions" true rather than aspirational.
// 2. Nothing analytics does may break a page, so every SDK entry point is wrapped.
// 3. Emission is gated on the SDK being READY *and* identified. Without the gate a track() on a
//    page where analytics is off does not no-op: the SDK's module-level track() pushes into a
//    pre-init queue that init() never drains, so it fills to its 1000-entry cap and holds those
//    objects for the life of the document, warning VEK_TRK_PRE_INIT_QUEUE_OVERFLOW on every call
//    after that — a warning the SDK does not gate on `debug`. A track() landing between init() and
//    identify() is dropped outright (VEK_TRK_MISSING_IDENTITY); the same gate prevents that too.
//
// The two exported names mirror the one decision §2 forces on a call site: did the user complete
// the thing the feature exists to do (used), or only touch its surface (engagement)? Making that
// the function name rather than a string argument means it cannot be defaulted or misspelled into
// an event type the schema does not have.

// The §5.2 closed property registry, transcribed from Vektis::Taxonomy::PROPERTY_KEYS. The two
// copies are asserted identical by test/services/vektis/property_registry_parity_test.rb, which is
// what keeps this list from drifting — there is no build step that could share the constant.
//
// Enforced here and not only reviewed, for the same reason Vektis::EventEmitter#audit strips rather
// than warns (VEK-587): properties is stored verbatim in impact_events.properties with no delete
// path, so an unreviewed key is unrecoverable once shipped. A call site reaching for a label name or
// a search query silently loses it here instead.
const PROPERTY_KEYS = new Set([
  "source", "via", "surface", "entity", "provider", "webhook_event", "from_position",
  "to_position", "direction", "priority", "count", "depth", "filter_type", "option", "tab",
  "shortcut", "query_length", "result_count", "has_project", "has_assignee", "has_estimate",
  "has_due_date", "is_sub_issue",
]);

// properties must be Record<string, string | number | boolean>. A single undefined value makes the
// server 400 the batch, and a 400 is a drop with no retry (§1) — one mistyped lookup would take
// every other event batched alongside it down with it. Drop bad values rather than ship them.
function scalarProperties(properties) {
  const cleaned = { source: "browser" };

  for (const [key, value] of Object.entries(properties)) {
    if (!PROPERTY_KEYS.has(key)) continue;

    const type = typeof value;
    if (type === "string" || type === "number" || type === "boolean") cleaned[key] = value;
  }

  return cleaned;
}

function ready() {
  const status = getStatus();
  return status.state === "READY" && status.identityCustomerId !== null;
}

function emit(eventType, featureId, action, properties) {
  try {
    // A feature.* event with no feature_id is a guaranteed server-side validation failure.
    if (!featureId) return;

    const payload = { feature_id: featureId, action, properties: scalarProperties(properties) };

    if (ready()) {
      track(eventType, payload);
      return;
    }

    // DISABLED is terminal — the ingest endpoint rejected the key and only a fresh init() recovers.
    if (getStatus().state === "DISABLED") return;

    // Stimulus connects <body> before its descendants, so vektis_controller has run init() and
    // identify() before any handler here can fire. This retry covers the case where that ordering
    // does not hold — a controller emitting from its own connect() in the same task. One macrotask
    // later, every connect() dispatched in that task has run. If the SDK is still not ready the
    // event is dropped on purpose: that is the analytics-disabled case, and handing it to the SDK
    // would only park it in a pre-init queue nothing will ever drain.
    setTimeout(() => {
      try {
        if (ready()) track(eventType, payload);
      } catch {
        // As below: never break the page.
      }
    }, 0);
  } catch {
    // Analytics is never worth a broken page. There is no debug flag readable from here, and a
    // console.error on every interaction would be worse than silence.
  }
}

// feature.used — the user completed the thing the feature exists to do (§2).
export function trackFeature(featureId, action, properties = {}) {
  emit("feature.used", featureId, action, properties);
}

// feature.engagement — the user touched the feature's surface without completing it (§2).
export function trackEngagement(featureId, action, properties = {}) {
  emit("feature.engagement", featureId, action, properties);
}
