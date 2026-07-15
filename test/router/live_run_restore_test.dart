// THE SCENE DIED ON THE SUCCESS PATH, AND NOTHING BROUGHT THE USER BACK.
//
// DEVICE EVIDENCE (build 202607141205 = 994c6fe, real iPhone, Keith, on Wi-Fi):
//   "Click on Check My Connection, and it opens the Shortcut for a second, then
//    RETURNS TO THE HOME SCREEN. Doesn't finish Test My Connection at all."
//
// THE CODEBASE DOCUMENTS THIS BUG IN ITS OWN HEADER AND ONLY FIXES HALF OF IT.
// `live_error_nav_gate.dart:4-12` says, verbatim, that "firing the one-shot
// backgrounds the app into the Shortcuts app, and iOS can tear down and rebuild our
// UIScene, so Flutter restarts at its initial (home) route. The originating tool
// screen is gone."
//
// It then fixes that for EXACTLY ONE CASE: the x-error (missing Shortcut) path.
// `LiveErrorNavGate` is driven by `consumeLiveErrorNav()`, a flag raised ONLY by the
// native x-error handler. On the SUCCESS path — the Shortcut is present and runs
// perfectly, which is Keith's case — there is no error, so `origin == null`, the
// gate no-ops at `:111`, and the user is stranded on Home with the run gone.
//
// AND A GREEN TEST ASSERTED THAT WAS FINE: live_error_nav_gate_test.dart's
// "no pending nav (null) leaves the user on home". That test is not wrong — a user
// who deliberately goes home MUST be left alone (see the COUNTERWEIGHT group). It
// was just the only case anyone had ever driven, so it read as a complete spec when
// it was half of one. Read the test NAMES before you trust a green suite.
//
// NOTHING IN 4,282 TESTS EVER DROVE A SCENE TEARDOWN ON THE SUCCESS PATH. That
// absence is why six cold reviews and three mutation rounds passed while Keith's
// phone failed in ten seconds, for the third time this week. This file drives it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/router/live_error_nav_gate.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';

/// THE APP GROUP — the only thing that survives a UIScene teardown, because it
/// lives BELOW the app's lifecycle. Everything else (the screen, its State, the
/// in-flight measurement, the whole Dart heap) is destroyed and rebuilt from zero.
class _AppGroup {
  /// Armed when a live tool fires a trigger as part of a run it means to finish;
  /// cleared on every CLEAN ending (run completed / errored / user left on purpose).
  /// So a marker still present at a home-restart MEANS "we did not exit cleanly".
  String? pendingRunRoute;
  DateTime? pendingRunAt;

  /// The x-error (missing-Shortcut) signal. FALSE throughout the success path —
  /// that is the entire point of these tests.
  bool errorNavPending = false;
  String originRoute = '';

  int clearLiveRunCalls = 0;
}

class _FakeBridge implements WiFiDetailsBridge {
  _FakeBridge(this.g);
  final _AppGroup g;

  @override
  Future<String?> consumeLiveErrorNav() async {
    if (!g.errorNavPending) return null;
    g.errorNavPending = false;
    return g.originRoute;
  }

  @override
  Future<void> armLiveRun(String route) async {
    g.pendingRunRoute = route;
    g.pendingRunAt = DateTime.now();
  }

  @override
  Future<PendingLiveRun?> pendingLiveRun() async {
    final String? r = g.pendingRunRoute;
    final DateTime? at = g.pendingRunAt;
    if (r == null || r.isEmpty || at == null) return null;
    return PendingLiveRun(route: r, armedAt: at);
  }

  @override
  Future<void> clearLiveRun() async {
    g.clearLiveRunCalls++;
    g.pendingRunRoute = null;
    g.pendingRunAt = null;
  }

  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The app wired exactly like main.dart: the shared navigator key, the route
/// observer, and the gate in the builder. Routes are stubbed to identifiable
/// scaffolds so a test can assert WHERE THE USER IS.
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

/// PUMPING A FRESH APP OVER A SURVIVING APP GROUP *IS* THE SCENE TEARDOWN.
///
/// That is not an approximation of the iOS event — it is structurally the same
/// thing. iOS destroys the UIScene, Flutter rebuilds the engine and restarts at its
/// initial (home) route with a brand-new widget tree, and the ONLY state that
/// crosses the gap is the App Group. A fresh `pumpWidget` over the same `_AppGroup`
/// reproduces precisely that: new tree, new State objects, same shared store.
Future<void> _sceneDestroyedAndRebuiltAtHome(
  WidgetTester tester,
  _AppGroup g,
) async {
  await tester.pumpWidget(_app(_FakeBridge(g)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // The observer is a shared singleton across the theme-driven MaterialApp
    // rebuilds; reset it so one test's route history cannot leak into the next.
    CurrentRouteObserver.currentRouteName = null;
  });

  group('THE RESTORE — iOS destroyed the scene mid-run (SUCCESS path)', () {
    testWidgets(
        'TEST 1: the scene is rebuilt at HOME with NO error flag → the user is '
        'routed BACK to Test My Connection', (WidgetTester tester) async {
      final _AppGroup g = _AppGroup();
      // Test My Connection fired the one-shot as part of a run it means to finish.
      // This arm is the only record of that run that can survive what happens next.
      g.pendingRunRoute = AppRouter.testMyConnection;
      g.pendingRunAt = DateTime.now();

      // THE SUCCESS PATH. The Shortcut is present and ran perfectly. There is no
      // x-error, so there is no pending-nav flag — which is exactly why the shipped
      // gate cannot see this case at all.
      expect(g.errorNavPending, isFalse,
          reason: 'the premise: nothing errored. iOS simply took our scene.');

      await _sceneDestroyedAndRebuiltAtHome(tester, g);

      expect(
        find.text('TMC'),
        findsOneWidget,
        reason: 'THE BUG. LiveErrorNavGate is driven by consumeLiveErrorNav(), '
            'which the x-error native handler raises. On the success path nothing '
            'errors, so origin == null and the gate no-ops (live_error_nav_gate.'
            'dart:111). Keith tapped "Check My Connection", the app bounced through '
            'Shortcuts, iOS rebuilt the scene, and he landed on HOME with the run '
            'gone. The route was RECORDED the whole time — the gate simply refused '
            'to use it unless something had errored.',
      );
      expect(find.text('HOME'), findsNothing);

      // THE GATE MUST NOT CONSUME THE ARM. It navigates; the TOOL resumes. If the
      // gate ate the marker here, the screen would mount one frame later, find
      // nothing pending, and render itself FRESH — putting Keith back on Test My
      // Connection with his run still gone. That is the bug with better manners, and
      // it is the single easiest way to "fix" this and ship it broken.
      expect(g.pendingRunRoute, AppRouter.testMyConnection,
          reason: 'the arm survives the navigation, for the screen to consume');
      expect(g.clearLiveRunCalls, 0);
    });

    testWidgets(
        'the restore honors the route that armed the run — Wi-Fi Information '
        'goes back to Wi-Fi Information, not to the front door',
        (WidgetTester tester) async {
      final _AppGroup g = _AppGroup()
        ..pendingRunRoute = AppRouter.wifiInfo
        ..pendingRunAt = DateTime.now();

      await _sceneDestroyedAndRebuiltAtHome(tester, g);

      expect(find.text('WIFI-INFO'), findsOneWidget);
      expect(find.text('TMC'), findsNothing,
          reason: 'restoring the WRONG tool is not a restore. The arm names the '
              'tool that was actually running.');
    });

    testWidgets('the restore lands on [home, tool] so Back still returns home',
        (WidgetTester tester) async {
      final _AppGroup g = _AppGroup()
        ..pendingRunRoute = AppRouter.testMyConnection
        ..pendingRunAt = DateTime.now();

      await _sceneDestroyedAndRebuiltAtHome(tester, g);
      expect(find.text('TMC'), findsOneWidget);

      // A restore must not trap the user in the tool it dragged them into.
      final NavigatorState nav = AppRouter.navigatorKey.currentState!;
      expect(nav.canPop(), isTrue);
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'the x-error path still wins when BOTH signals are somehow present '
        '(the recovery card outranks a resume that cannot succeed)',
        (WidgetTester tester) async {
      // Belt-and-braces: markShortcutMissing() disarms the run natively, so this
      // should be unreachable. If it ever happens, the honest "Shortcut not found"
      // recovery is the correct destination — a resume would wait on a payload that
      // provably cannot arrive.
      final _AppGroup g = _AppGroup()
        ..errorNavPending = true
        ..originRoute = AppRouter.wifiInfo
        ..pendingRunRoute = AppRouter.testMyConnection
        ..pendingRunAt = DateTime.now();

      await _sceneDestroyedAndRebuiltAtHome(tester, g);

      expect(find.text('WIFI-INFO'), findsOneWidget,
          reason: 'the x-error origin, not the armed run, drives this one');
    });
  });

  group('THE COUNTERWEIGHT — a user who meant to leave is LEFT ALONE', () {
    testWidgets(
        'TEST 3: the user DELIBERATELY navigated home → they are NOT yanked back '
        'into a tool', (WidgetTester tester) async {
      // A clean exit DISARMS the run. That is what makes "the marker is still set"
      // mean "we did not exit cleanly" — and it is the whole discriminator between
      // Keith's destroyed scene and an ordinary Back tap.
      final _AppGroup g = _AppGroup(); // nothing armed

      await _sceneDestroyedAndRebuiltAtHome(tester, g);

      expect(find.text('HOME'), findsOneWidget,
          reason: 'THE BEHAVIOR THE OLD TEST WAS PROTECTING, AND IT IS '
              'LEGITIMATE. An app that drags you back into a screen you just left '
              'is broken in a different, more annoying way. The restore must fix '
              'the destroyed run WITHOUT swallowing this case.');
      expect(find.text('TMC'), findsNothing);
      expect(find.text('WIFI-INFO'), findsNothing);
    });

    testWidgets(
        'a STALE arm (older than the restore window) is IGNORED — and cleared, so '
        'it can never fire later', (WidgetTester tester) async {
      // iOS killed the app mid-run and the user reopened it the next morning. The
      // run is long gone; dragging them into a tool now is the app hijacking their
      // navigation, not recovering their work.
      final _AppGroup g = _AppGroup()
        ..pendingRunRoute = AppRouter.testMyConnection
        ..pendingRunAt = DateTime.now()
            .subtract(PendingLiveRun.restoreWindow + const Duration(seconds: 1));

      await _sceneDestroyedAndRebuiltAtHome(tester, g);

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('TMC'), findsNothing);
      expect(g.pendingRunRoute, isNull,
          reason: 'a stale arm must be REAPED, not merely skipped — otherwise it '
              'sits in the App Group waiting to ambush a future launch');
    });

    testWidgets('an arm barely INSIDE the window still restores',
        (WidgetTester tester) async {
      // The boundary in the other direction: a slow cold relaunch must not lose the
      // run. Pins that the window is a real window, not a rounding artifact.
      final _AppGroup g = _AppGroup()
        ..pendingRunRoute = AppRouter.testMyConnection
        ..pendingRunAt = DateTime.now()
            .subtract(PendingLiveRun.restoreWindow - const Duration(seconds: 5));

      await _sceneDestroyedAndRebuiltAtHome(tester, g);

      expect(find.text('TMC'), findsOneWidget);
    });

    testWidgets(
        'an arm for a route that is not a live tool does NOT navigate anywhere',
        (WidgetTester tester) async {
      // Fail safe. An unrecognized route is not an invitation to guess: the x-error
      // path can fall back to the front door because it has a recovery card to show,
      // but a RESTORE has nothing to restore on a screen that never armed a run.
      final _AppGroup g = _AppGroup()
        ..pendingRunRoute = '/tools/some-non-live-tool'
        ..pendingRunAt = DateTime.now();

      await _sceneDestroyedAndRebuiltAtHome(tester, g);

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('TMC'), findsNothing);
    });

    testWidgets(
        'already ON the tool (a warm return, scene intact) → no re-push, and the '
        'arm is left for the screen to consume', (WidgetTester tester) async {
      final _AppGroup g = _AppGroup()
        ..pendingRunRoute = AppRouter.testMyConnection
        ..pendingRunAt = DateTime.now();
      final _FakeBridge bridge = _FakeBridge(g);

      await tester.pumpWidget(_app(bridge));
      await tester.pumpAndSettle();
      // We are now on TMC via the restore.
      expect(find.text('TMC'), findsOneWidget);

      // A second foreground (the app was merely backgrounded, not destroyed). The
      // gate must not re-push TMC on top of itself — that would rebuild the screen
      // and destroy the very run it just restored.
      final int before = g.clearLiveRunCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('TMC'), findsOneWidget);
      expect(g.clearLiveRunCalls, before,
          reason: 'the GATE never consumes the arm — the SCREEN does, once it has '
              'actually taken the run over. A gate that consumed it would starve '
              'the resume and land the user on a reset screen.');
    });
  });
}
