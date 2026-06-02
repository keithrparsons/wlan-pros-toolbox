// Deep-link router for the one-tap Shortcut trigger return (TICKET-03 UX fix).
//
// THE PROBLEM (observed on a real iPhone): after the flick to Shortcuts, iOS
// frequently kills the backgrounded release app and cold-relaunches it for the
// x-callback. On return the app had no listening screen, so the Navigator sat
// on its HOME/root screen instead of the tool the user triggered from. The first
// tap "worked" only because the app happened to stay warm that once.
//
// THE FIX: the x-callback now carries the originating tool id + status
// (`wlanprostoolbox://reading?tool=wifi-info&status=ok`). This widget wraps the
// app, subscribes to BOTH iOS Shortcut bridges' `triggerEvents` streams, and on
// each return deep-links to that tool's route via [AppRouter.navigatorKey] —
// reusing the existing named-route Navigator, not a second nav system. It covers
// both paths:
//   * WARM resume  — the event arrives live; if the tool route is not already on
//                    top, navigate to it. The destination screen re-reads the
//                    App Group payload on init/resume and refreshes.
//   * COLD launch  — the native side buffered the callback before the engine was
//                    up and replays it the instant the stream is listened to
//                    (here). We navigate from scratch to the tool route. This is
//                    the case that used to strand the user on home.
//
// On `status=err` it routes to the SAME tool screen and passes
// [ShortcutTriggerArgs.initialError] so the screen shows its honest error banner
// there (not the home screen). A tool-less legacy return (no tool segment) is a
// no-op here — the already-listening screen refreshes itself in place.
//
// Non-iOS: the bridges' channels have no handler, so `triggerEvents` stays empty
// and this widget is inert. Normal app launch (no deep-link URL) never produces
// an event, so the app opens to home as usual.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/network/cellular_info_bridge.dart';
import '../services/network/shortcut_trigger_result.dart';
import '../services/network/wifi_details_bridge.dart';
import 'app_router.dart';

/// Route arguments carried into a tool screen reached via a one-tap-trigger
/// deep link. [initialError] is true when the return was `status=err`, so the
/// destination screen surfaces its honest error banner immediately.
class ShortcutTriggerArgs {
  const ShortcutTriggerArgs({required this.initialError});

  final bool initialError;
}

/// Wraps the app and routes one-tap-trigger x-callback returns to the
/// originating tool screen (warm + cold). Injectable streams keep it testable
/// without a platform channel.
class ShortcutDeepLinkRouter extends StatefulWidget {
  const ShortcutDeepLinkRouter({
    super.key,
    required this.child,
    this.wifiEvents,
    this.cellularEvents,
  });

  final Widget child;

  /// Override the Wi-Fi trigger-event stream (tests). Defaults to the real
  /// [WiFiDetailsBridge.triggerEvents].
  final Stream<ShortcutTriggerEvent>? wifiEvents;

  /// Override the cellular trigger-event stream (tests). Defaults to the real
  /// [CellularInfoBridge.triggerEvents].
  final Stream<ShortcutTriggerEvent>? cellularEvents;

  @override
  State<ShortcutDeepLinkRouter> createState() => _ShortcutDeepLinkRouterState();
}

class _ShortcutDeepLinkRouterState extends State<ShortcutDeepLinkRouter> {
  final List<StreamSubscription<ShortcutTriggerEvent>> _subs =
      <StreamSubscription<ShortcutTriggerEvent>>[];

  @override
  void initState() {
    super.initState();
    // Listening here is what flushes the native cold-launch buffer: the moment
    // these streams are subscribed, the native side replays any callback that
    // arrived before the engine was up (see AppDelegate.setTriggerResultSink).
    final Stream<ShortcutTriggerEvent> wifi =
        widget.wifiEvents ?? WiFiDetailsBridge().triggerEvents;
    final Stream<ShortcutTriggerEvent> cellular =
        widget.cellularEvents ?? CellularInfoBridge().triggerEvents;
    _subs.add(wifi.listen(_onEvent));
    _subs.add(cellular.listen(_onEvent));
  }

  @override
  void dispose() {
    for (final StreamSubscription<ShortcutTriggerEvent> s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  /// Routes a decoded trigger return to its tool screen. A tool-less return is a
  /// no-op (the listening screen refreshes itself in place); an unknown tool id
  /// is a no-op (the user stays put rather than bouncing to home).
  void _onEvent(ShortcutTriggerEvent event) {
    final String? toolId = event.tool;
    if (toolId == null) return;
    final String? route = AppRouter.routeForTriggerTool(toolId);
    if (route == null) return;

    final NavigatorState? nav = AppRouter.navigatorKey.currentState;
    if (nav == null) return;

    final ShortcutTriggerArgs args = ShortcutTriggerArgs(
      initialError: event.result == ShortcutTriggerResult.error,
    );

    // Navigate to the tool route if it is not already on top. On a cold launch
    // the stack is just [home], so this pushes the tool screen; on a warm resume
    // where the tool is already foreground we skip the redundant push and let the
    // screen's own resume re-read refresh it (the error flag, if any, is applied
    // by the live triggerResults listener on that screen).
    if (_currentRouteName(nav) == route) return;
    nav.pushNamed(route, arguments: args);
  }

  /// The name of the route currently on top of [nav], or null.
  String? _currentRouteName(NavigatorState nav) {
    String? name;
    nav.popUntil((Route<dynamic> route) {
      name = route.settings.name;
      return true; // inspect only; never actually pops
    });
    return name;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
