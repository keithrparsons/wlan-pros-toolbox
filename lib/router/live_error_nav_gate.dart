// LiveErrorNavGate — routes the user back to the originating live tool after a
// missing-Shortcut x-error, so the recovery card shows instead of the home strand.
//
// WHY THIS EXISTS (2026-06-26, Keith device round 3): after setup succeeded, a
// user who later RENAMED/deleted "WLAN Pros Live" and tapped a live action saw the
// app briefly open Shortcuts, then bounce back (the x-error return fires, no
// strand on the Shortcuts page) — BUT it landed on the HOME page with no recovery
// message. The cause: firing the one-shot backgrounds the app into the Shortcuts
// app, and on a missing Shortcut iOS can tear down and rebuild our UIScene, so
// Flutter restarts at its initial (home) route. The originating tool screen is
// gone, so nothing consumes the shortcut-missing marker and the recovery never
// shows.
//
// The fix: each live tool records its route in the App Group when it opens; the
// x-error native handler raises a pending-nav flag; and this gate, on foreground
// (and at startup), routes the user back to that tool — where its load() consumes
// the marker and renders "Live Wi-Fi Shortcut not found — re-run setup". It only
// re-routes when the user is NOT already on the origin tool, so it never races the
// tool's own resume-load (which already shows the recovery on a warm return).

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
    final String? origin = await _bridge.consumeLiveErrorNav();
    // Null = no x-error nav pending (the normal case) → do nothing.
    if (origin == null || !mounted) return;
    final String target =
        _liveRoutes.contains(origin) ? origin : AppRouter.testMyConnection;
    // Already on the origin tool (warm return): its own resume-load shows the
    // recovery, so don't re-push (which would rebuild it and race the marker).
    if (CurrentRouteObserver.currentRouteName == target) return;
    final NavigatorState? nav = AppRouter.navigatorKey.currentState;
    if (nav == null) return;
    // Land on [home, tool] so Back returns home; the tool's load() then consumes
    // the missing-Shortcut marker and renders the recovery card.
    nav.pushNamedAndRemoveUntil(target, (Route<dynamic> r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
