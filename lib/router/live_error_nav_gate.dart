// LiveErrorNavGate — puts the user back on the live tool that iOS took away from
// them, whether the trip through Shortcuts FAILED or SUCCEEDED.
//
// THE ROOT CAUSE, WHICH IS THE SAME FOR BOTH (2026-06-26 and 2026-07-14):
// firing a Shortcut backgrounds the app into the Shortcuts app, and iOS can TEAR
// DOWN AND REBUILD OUR UISCENE while we are away. Flutter then restarts at its
// initial (home) route, and the ENTIRE DART HEAP goes with it — the tool screen,
// its state, and any measurement in flight. The user tapped a button and landed on
// Home with nothing.
//
// THIS FILE ORIGINALLY FIXED ONLY THE ERROR HALF, AND SAID SO IN THIS HEADER.
//
//   ROUND 3 (2026-06-26) — the FAILURE case. A user who renamed/deleted "WLAN Pros
//   Live" tapped a live action, bounced through Shortcuts, and landed on HOME with
//   no recovery message. Fix: the x-error native handler raises a pending-nav flag,
//   and this gate routes back to the tool, where its load() renders "Shortcut not
//   found — re-run setup".
//
//   ROUND 6 (2026-07-14, Keith device) — the SUCCESS case, which had been sitting
//   right next to it the whole time. "Click on Check My Connection, and it opens
//   the Shortcut for a second, then RETURNS TO THE HOME SCREEN. Doesn't finish Test
//   My Connection at all." His Shortcut was PERFECT. It ran. There was no error —
//   and therefore no error flag, so `consumeLiveErrorNav()` returned null, this gate
//   no-opped, and he was stranded exactly as before. The gate was keyed on the
//   FAILURE rather than on the LOSS, and the loss happens either way.
//
// A crash is not the only thing that can destroy a screen. Success destroys it too.
//
// TWO SIGNALS, TWO RECOVERIES:
//   * `consumeLiveErrorNav()` — the Shortcut is MISSING → route back, show the
//     honest "re-run setup" card. (There is no run to resume; there never was one.)
//   * `pendingLiveRun()`      — a run was IN FLIGHT and never disarmed → route back,
//     and the TOOL resumes the run from the reading the Shortcut left in the App
//     Group. Routing back alone would hand the user a RESET SCREEN, which is not a
//     fix; see `test_my_connection_screen.dart`'s resume path.
//
// The arm/disarm discipline is what keeps this from hijacking navigation: a run is
// armed only at the moment it fires a trigger, and disarmed on every clean ending.
// A user who deliberately walks home has no arm, so nothing drags them back.

import 'package:flutter/material.dart';

import '../services/network/wifi_details_bridge.dart';
import 'app_router.dart';

/// Tracks the current top route name so [LiveErrorNavGate] can tell a cold
/// relaunch-to-home (re-route needed) from a warm return that is already on the
/// origin tool (re-route would be redundant and race the tool's own recovery).
/// Registered in `MaterialApp.navigatorObservers`.
class CurrentRouteObserver extends NavigatorObserver {
  /// The name of the route currently on top, or null before the first push.
  static String? currentRouteName;

  void _set(Route<dynamic>? route) {
    final String? name = route?.settings.name;
    if (name != null) currentRouteName = name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _set(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);
}

/// Single shared observer instance so the route table is stable across the
/// theme-driven [MaterialApp] rebuilds.
final CurrentRouteObserver appRouteObserver = CurrentRouteObserver();

/// Wraps the app body, observes the lifecycle, and on a pending x-error nav routes
/// the user back to the originating live tool. A no-op on every normal foreground.
class LiveErrorNavGate extends StatefulWidget {
  const LiveErrorNavGate({super.key, required this.child, this.bridge});

  final Widget child;

  /// Injectable for tests; defaults to the real shared-channel bridge. Off-iOS the
  /// channel has no handler and [consumeLiveErrorNav] returns null (no-op).
  final WiFiDetailsBridge? bridge;

  @override
  State<LiveErrorNavGate> createState() => _LiveErrorNavGateState();
}

class _LiveErrorNavGateState extends State<LiveErrorNavGate>
    with WidgetsBindingObserver {
  late final WiFiDetailsBridge _bridge;

  /// The live tools the x-error recovery can route to. Any unrecognized origin
  /// falls back to the consumer front door (Test My Connection).
  static const Set<String> _liveRoutes = <String>{
    AppRouter.wifiInfo,
    AppRouter.testMyConnection,
    AppRouter.cellularInfo,
  };

  @override
  void initState() {
    super.initState();
    _bridge = widget.bridge ?? WiFiDetailsBridge();
    WidgetsBinding.instance.addObserver(this);
    // Cold relaunch via the x-error URL lands here at the initial route; check once
    // after the first frame so the navigator exists.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    // ---- PATH 1: THE x-ERROR (the Shortcut is MISSING). Unchanged. ----
    final String? origin = await _bridge.consumeLiveErrorNav();
    if (origin != null) {
      if (!mounted) return;
      final String target =
          _liveRoutes.contains(origin) ? origin : AppRouter.testMyConnection;
      // The tool's own load() consumes the missing-Shortcut marker and renders
      // "Shortcut not found — re-run setup".
      _routeTo(target);
      return;
    }
    if (!mounted) return;

    // ---- PATH 2: THE SUCCESS PATH. iOS DESTROYED OUR SCENE MID-RUN. ----
    //
    // THIS IS THE HALF THAT WAS MISSING, AND IT IS THE HALF KEITH KEPT HITTING.
    //
    // Everything above only fires when something ERRORED. But Keith's Shortcut was
    // fine — it ran perfectly. The app fired the one-shot, iOS foregrounded
    // Shortcuts, tore down our UIScene, and rebuilt Flutter at its initial (home)
    // route. No error, so no pending-nav flag, so `origin == null`, so this method
    // used to simply RETURN — and he was left on Home with his run gone. The
    // originating route was recorded the entire time (every live tool calls
    // `setLiveOriginRoute` on open); the gate just refused to use it unless
    // something had failed.
    //
    // A crash is not the only way to lose a screen. Success can lose it too.
    await _restoreInterruptedRun();
  }

  /// Puts the user back on the tool that had a run IN FLIGHT when the scene died.
  ///
  /// THE DISCRIMINATOR. The hard part here is not navigating — it is knowing WHEN
  /// to. "The user is on Home and a live tool was open" describes both the destroyed
  /// scene AND a user who simply tapped Back, and dragging that second user into a
  /// tool they deliberately left would be its own bug.
  ///
  /// So the signal is not "a tool was open" — it is "a RUN WAS ARMED AND NEVER
  /// DISARMED". The tool arms at the instant it fires the trigger and disarms on
  /// every clean ending (the run completes, the run errors, the user leaves on
  /// purpose). An arm that is still standing therefore MEANS, and can only mean, "we
  /// did not exit cleanly" — which is precisely the fact we need and nothing else in
  /// the App Group carries.
  Future<void> _restoreInterruptedRun() async {
    final PendingLiveRun? pending = await _bridge.pendingLiveRun();
    if (pending == null || !mounted) return;

    // A run armed longer ago than the restore window is not a run any more — iOS
    // killed the app and the user came back later. REAP it (do not merely skip it),
    // or it sits in the App Group waiting to ambush some future launch.
    if (!pending.isFresh()) {
      await _bridge.clearLiveRun();
      return;
    }

    // FAIL SAFE ON AN UNKNOWN ROUTE. The x-error path may fall back to the front
    // door because it has a recovery card to show there. A RESTORE has nothing to
    // restore on a screen that never armed a run, so it navigates NOWHERE rather
    // than guessing.
    if (!_liveRoutes.contains(pending.route)) return;

    _routeTo(pending.route);
    // NOTE: THE GATE DOES NOT CONSUME THE ARM. The tool does, once it has actually
    // taken the run over. A consume here would swallow the evidence one frame before
    // the screen reads it, and the user would land on a freshly reset tool with the
    // run gone — which is the bug, wearing the fix's clothes.
  }

  /// Lands on `[home, tool]` so Back still returns home, and never re-pushes a tool
  /// the user is already on (which would rebuild it and destroy the very run we are
  /// trying to restore).
  void _routeTo(String target) {
    if (CurrentRouteObserver.currentRouteName == target) return;
    final NavigatorState? nav = AppRouter.navigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil(target, (Route<dynamic> r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
