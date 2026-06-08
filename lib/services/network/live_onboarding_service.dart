// LiveOnboardingService — the one-time first-run gate for the iOS live tools.
//
// WHY THIS EXISTS: on iOS the live Wi-Fi tools cannot read RF data until the
// user installs the "WLAN Pros Live" companion Shortcut (iOS exposes no public
// API for RSSI / channel / PHY / Tx-Rx for the connected network — see Pax's
// 2026-06-07 onboarding research). Beta testers (IT pros) opened the Test My
// Connection front door, ran a check, and only AFTER the result were told the
// Shortcut existed — so the tool looked broken on first use. This service makes
// the "enable live Wi-Fi" setup unmissable: the FIRST time the user opens ANY
// live tool (including the front door) we present the setup sheet once.
//
// HONEST install-state (GL-005): iOS cannot report whether a Shortcut is
// installed, so we never claim a fake "installed". We combine TWO honest
// signals to decide whether to show the first-run sheet:
//   1. hasEverReceivedPayload (App Group flag, owned by WiFiDetailsBridge) — if
//      the app has EVER received a Live payload the Shortcut demonstrably works,
//      so we never onboard.
//   2. a persisted "first-run onboarding seen" flag (this service) — so a user
//      who has been shown the sheet once is never nagged again, even if they
//      have not yet completed the install.
//
// Persistence is via shared_preferences (one bool key), mirroring
// [ThemeController]. A read/write failure must never block a tool — the service
// degrades to "treat as already seen" on a read error (we do not want a storage
// fault to spam the sheet on every open) and silently no-ops on a write error.

import 'package:shared_preferences/shared_preferences.dart';

/// Reads/writes the persisted "user has been through live-Wi-Fi onboarding"
/// flag. iOS-only in practice (macOS reads CoreWLAN natively and never onboards;
/// callers gate on the platform before consulting this service), but the class
/// itself is platform-agnostic and fully unit-testable via the injected store.
class LiveOnboardingService {
  /// [getStore] defaults to the real [SharedPreferences]; tests inject a fake.
  LiveOnboardingService({
    Future<SharedPreferences> Function()? getStore,
  }) : _getStore = getStore ?? SharedPreferences.getInstance;

  /// The shared_preferences key for the persisted first-run-seen flag.
  static const String prefsKey = 'live_onboarding_seen_v1';

  final Future<SharedPreferences> Function() _getStore;

  /// Whether the first-run onboarding sheet has already been shown to the user.
  ///
  /// On a storage read failure this resolves to `true` (treat as seen) so a
  /// broken store can never spam the setup sheet on every tool open. The caller
  /// pairs this with the honest [WiFiDetailsBridge.hasEverReceivedPayload]
  /// signal, so a user who actually has the Shortcut is covered by that path
  /// regardless of what this returns.
  Future<bool> hasSeenOnboarding() async {
    try {
      final SharedPreferences prefs = await _getStore();
      return prefs.getBool(prefsKey) ?? false;
    } catch (_) {
      // Storage unavailable → do not risk nagging; treat as already seen.
      return true;
    }
  }

  /// Records that the first-run onboarding has been shown, so it never fires
  /// again. A persist failure is swallowed (the in-session decision still holds
  /// for this run; the worst case is one extra prompt on a future launch).
  Future<void> markOnboardingSeen() async {
    try {
      final SharedPreferences prefs = await _getStore();
      await prefs.setBool(prefsKey, true);
    } catch (_) {
      // Persist failed → no crash; the flag simply is not durable this run.
    }
  }

  /// The composite decision: should the first-run "enable live Wi-Fi" sheet be
  /// presented now?
  ///
  /// True only when BOTH honest signals say the user is brand-new to live Wi-Fi:
  ///   * the app has NEVER received a Live payload ([hasEverReceivedPayload] —
  ///     so the Shortcut is not demonstrably working), AND
  ///   * the onboarding sheet has NOT been shown before ([hasSeenOnboarding]).
  ///
  /// [hasEverReceivedPayload] is passed in by the caller (read from the host
  /// tool's [WiFiDetailsBridge]) so this service owns only the persisted flag
  /// and never reaches into a platform channel itself — keeping it trivially
  /// testable and side-effect-free.
  Future<bool> shouldShowOnboarding({
    required bool hasEverReceivedPayload,
  }) async {
    if (hasEverReceivedPayload) return false;
    final bool seen = await hasSeenOnboarding();
    return !seen;
  }
}
