import { Controller } from "@hotwired/stimulus";
import { getStatus, identify, init, reset, track } from "@vektis-io/tracker";

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
// Switching TEAMS is the one case that does need a reset(). Each team is its own VEKTIS tenant
// with its own API key, and the key is fixed at init() — getStatus() reports the identity but not
// the key, so the SDK cannot be asked which one it holds. We remember it here and, when the page
// renders a different one, tear the SDK down and init() it again. Without that, every event after
// a team switch would be delivered under the previous team's key and land in the wrong account.
//
// Ordering caveat for future call sites: pre-init() track() calls are buffered and replayed by
// init(), but replay happens before the identify() below, so a sibling controller tracking from
// its own connect() would have that first event dropped. Track from interaction handlers.

// session.active is billable and controllers reconnect constantly here, so it fires once per
// identity per tab. Keyed by customer id AND user id: a second user signing in to the same tab
// still gets one, and so does the same user after switching to a team that is a different VEKTIS
// tenant — that tenant has seen no session at all yet.
const SESSION_ACTIVE_KEY = "vektis:session-active";

// The API key the SDK singleton was last init()ed with, so a team switch can be detected. Module
// scope, not instance state: Turbo replaces <body> on every visit, so the controller instance is
// new each time while the SDK module singleton survives.
let initializedKey = null;

// Fallback for privacy modes where sessionStorage throws on access.
let sessionActiveFallback = null;

function sessionActiveSent(identity) {
  try {
    return window.sessionStorage.getItem(`${SESSION_ACTIVE_KEY}:${identity}`) === "1";
  } catch {
    return sessionActiveFallback === identity;
  }
}

function markSessionActiveSent(identity) {
  sessionActiveFallback = identity;
  try {
    window.sessionStorage.setItem(`${SESSION_ACTIVE_KEY}:${identity}`, "1");
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
    try {
      // The SDK is an ES module with no global, so expose a console seam in development.
      if (this.debugValue) window.vektisDebug = { getStatus, identify, track };

      // No key means this team has not connected VEKTIS. That is not simply "do nothing": the SDK
      // singleton survives Turbo navigation, so an identity left over from a team that IS
      // connected would still be READY here, and every sibling controller's track() would file
      // this team's activity under the previous team's account. Tear it down.
      if (!this.keyValue) {
        this.teardown();
        return;
      }

      // A different team's key means the SDK is pointed at the wrong tenant. reset() returns it
      // to UNINITIALIZED so the init() below re-runs; identityChanged() is then true against the
      // cleared status, so identify() re-runs too.
      if (initializedKey !== null && initializedKey !== this.keyValue) {
        this.teardown();
      }

      // One snapshot, taken after any reset above, drives both decisions below.
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
        initializedKey = this.keyValue;
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

  // reset() is the only way back to UNINITIALIZED, which is what makes ready() false in
  // vektis.js and stops sibling call sites emitting. Safe to call when already uninitialized.
  teardown() {
    if (initializedKey === null && getStatus().state === "UNINITIALIZED") return;

    reset();
    initializedKey = null;
  }

  identityChanged(status) {
    return (
      status.identityCustomerId !== this.customerIdValue ||
      status.identityUserId !== this.userIdValue
    );
  }

  trackSessionActive() {
    const identity = `${this.customerIdValue}:${this.userIdValue}`;
    if (sessionActiveSent(identity)) return;

    // This type takes neither a feature_id nor an action.
    track("session.active", { properties: { source: "browser" } });
    markSessionActiveSent(identity);
  }

  // Terminal state, entered on a 401 from the ingest endpoint: identify() and track() are
  // permanent no-ops from here. Recovery needs a fresh init(), which a bad key would only
  // fail again, so surface it rather than retry.
  logDisabled() {
    if (!this.debugValue) return;

    console.error(
      "[Vektis] SDK is DISABLED — the ingest endpoint rejected the API key. " +
        "Check the team's publishable key in team settings > Analytics, then reload."
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
