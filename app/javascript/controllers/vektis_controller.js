import { Controller } from "@hotwired/stimulus";
import { getStatus, identify, init, track } from "@vektis-io/tracker";

// Bootstraps the VEKTIS browser SDK. init() then identify(), in that order, before any
// track() call site can emit — a track() with no identity is silently dropped by the SDK
// (VEK_TRK_MISSING_IDENTITY), so this controller is a prerequisite for all instrumentation.
//
// Attached from <body> in layouts/application.html.erb via VektisHelper#vektis_controller_token,
// which gates the token on exactly the conditions that render the values read below. No key
// means analytics is off, so connect() is a no-op.
//
// Turbo Drive replaces <body> without a page load: the SDK module singleton and its in-memory
// identity survive in-app navigation while connect() fires again on every visit. Both branches
// below are therefore guarded on the SDK's own reported state rather than on a local flag.
//
// Sign-out deliberately does not reset() the SDK. A logout -> login cycle is two Turbo visits
// with no page load, so the previous user's identity outlives it; reconciling the rendered user
// against getStatus() on every connect is what keeps user B's events off user A, and it also
// self-heals after session expiry and full page loads (VEK-580).
//
// Ordering caveat for future call sites: pre-init() track() calls are buffered and replayed by
// init(), but replay happens before the identify() below, so a sibling controller tracking from
// its own connect() would have that first event dropped. Track from interaction handlers.

// session.active is billable and controllers reconnect constantly here, so it fires once per
// user per tab. Keyed by user id so a second user signing in to the same tab still gets one.
const SESSION_ACTIVE_KEY = "vektis:session-active";

// Fallback for privacy modes where sessionStorage throws on access.
let sessionActiveFallback = null;

function sessionActiveSent(userId) {
  try {
    return window.sessionStorage.getItem(`${SESSION_ACTIVE_KEY}:${userId}`) === "1";
  } catch {
    return sessionActiveFallback === userId;
  }
}

function markSessionActiveSent(userId) {
  sessionActiveFallback = userId;
  try {
    window.sessionStorage.setItem(`${SESSION_ACTIVE_KEY}:${userId}`, "1");
  } catch {
    // Nothing to do: sessionActiveFallback already covers this tab's lifetime.
  }
}

export default class extends Controller {
  static values = {
    key: String,
    endpoint: String,
    customerId: String,
    userId: String,
    debug: Boolean,
  };

  connect() {
    if (!this.keyValue) return;

    try {
      // The SDK is an ES module with no global, so expose a console seam in development.
      if (this.debugValue) window.vektisDebug = { getStatus, identify, track };

      // One snapshot, taken before init(), drives both decisions below.
      const status = getStatus();

      if (status.state === "DISABLED") {
        this.logDisabled();
        return;
      }

      if (status.state === "UNINITIALIZED") {
        init({
          apiKey: this.keyValue,
          // The SDK's own default is production and it fills this field with ??, so an
          // empty string would not fall back — pass undefined instead.
          endpoint: this.endpointValue || undefined,
          debug: this.debugValue,
        });
      }

      if (this.identityChanged(status)) {
        // identify() enqueues customer.identified itself. Snake_case is the SDK's input
        // shape; getStatus() reports the same two fields in camelCase.
        identify({ customer_id: this.customerIdValue, user_id: this.userIdValue });
        this.trackSessionActive();
      }
    } catch (error) {
      // keyboard-shortcuts, sidebar and notification-drawer share this element. Analytics
      // failing must never take them down with it.
      this.logError(error);
    }
  }

  identityChanged(status) {
    return (
      status.identityCustomerId !== this.customerIdValue ||
      status.identityUserId !== this.userIdValue
    );
  }

  trackSessionActive() {
    if (sessionActiveSent(this.userIdValue)) return;

    // This type takes neither a feature_id nor an action.
    track("session.active", { properties: { source: "browser" } });
    markSessionActiveSent(this.userIdValue);
  }

  // Terminal state, entered on a 401 from the ingest endpoint: identify() and track() are
  // permanent no-ops from here. Recovery needs a fresh init(), which a bad key would only
  // fail again, so surface it rather than retry.
  logDisabled() {
    if (!this.debugValue) return;

    console.error(
      "[Vektis] SDK is DISABLED — the ingest endpoint rejected the API key. " +
        "Check VEKTIS_PUBLISHABLE_KEY and VEKTIS_ENDPOINT, then reload."
    );
  }

  logError(error) {
    if (!this.debugValue) return;

    console.error(
      "[Vektis] analytics bootstrap failed; the rest of the page is unaffected.",
      error
    );
  }
}
