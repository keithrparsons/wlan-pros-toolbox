// Tests for LiveErrorNavGate — the x-error recovery navigation gate.
//
// On a missing-Shortcut x-error iOS may rebuild the scene at the home route,
// stranding the user there. The gate reads the pending-nav signal on foreground
// and routes back to the originating live tool (where its recovery card shows),
// but only when the user is NOT already on that tool (so it never races the
// tool's own resume-load consuming the recovery marker). A null consume result
// (the normal case) is a no-op.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/router/live_error_nav_gate.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';

/// A bridge whose consumeLiveErrorNav returns a scripted value once.
class _FakeBridge implements WiFiDetailsBridge {
  _FakeBridge(this._navResult);

  String? _navResult;
  int consumeCalls = 0;

  @override
  Future<String?> consumeLiveErrorNav() async {
    consumeCalls++;
    final String? v = _navResult;
    _navResult = null; // one-shot consume, mirroring native
    return v;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal app wired like main.dart: the shared navigator key, the route observer,
/// and the gate in the builder. Routes are stubbed to identifiable scaffolds.
Widget _app(WiFiDetailsBridge bridge) {
  Widget page(String label) => Scaffold(body: Center(child: Text(label)));
  return MaterialApp(
    navigatorKey: AppRouter.navigatorKey,
    navigatorObservers: <NavigatorObserver>[appRouteObserver],
    initialRoute: AppRouter.home,
    routes: <String, WidgetBuilder>{
      AppRouter.home: (_) => page('HOME'),
      AppRouter.wifiInfo: (_) => page('WIFI-INFO'),
      AppRouter.testMyConnection: (_) => page('TMC'),
      AppRouter.cellularInfo: (_) => page('CELLULAR'),
    },
    builder: (BuildContext context, Widget? child) =>
        LiveErrorNavGate(bridge: bridge, child: child!),
  );
}

void main() {
  testWidgets('cold relaunch to home routes to the origin tool', (tester) async {
    final bridge = _FakeBridge(AppRouter.wifiInfo);
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    // The post-frame check consumed the pending nav and pushed the origin tool.
    expect(bridge.consumeCalls, greaterThanOrEqualTo(1));
    expect(find.text('WIFI-INFO'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('an unknown origin falls back to Test My Connection',
      (tester) async {
    final bridge = _FakeBridge('/tools/some-non-live-tool');
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    expect(find.text('TMC'), findsOneWidget);
  });

  testWidgets('empty origin falls back to Test My Connection', (tester) async {
    final bridge = _FakeBridge('');
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    expect(find.text('TMC'), findsOneWidget);
  });

  testWidgets('no pending nav (null) leaves the user on home', (tester) async {
    final bridge = _FakeBridge(null);
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    expect(bridge.consumeCalls, greaterThanOrEqualTo(1));
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('WIFI-INFO'), findsNothing);
  });

  testWidgets('landing on [home, tool]: Back returns to home', (tester) async {
    final bridge = _FakeBridge(AppRouter.cellularInfo);
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    expect(find.text('CELLULAR'), findsOneWidget);
    // pushNamedAndRemoveUntil kept the first (home) route, so Back pops to home.
    final NavigatorState nav = AppRouter.navigatorKey.currentState!;
    expect(nav.canPop(), isTrue);
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });
}
