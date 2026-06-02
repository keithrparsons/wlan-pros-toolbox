// Deep-link router tests (TICKET-03 UX fix).
//
// Verifies the one-tap-trigger x-callback return deep-links to the ORIGINATING
// tool screen instead of stranding the user on home — the cold-relaunch case
// observed on a real iPhone. Three layers:
//
//   1. Wire decode — ShortcutTriggerEvent.fromNative parses "<tool>|<ok|err>".
//   2. Tool→route resolution — AppRouter.routeForTriggerTool.
//   3. Router behavior — a simulated cold-launch event (status=ok) navigates to
//      the correct tool route and shows the screen's values; status=err
//      navigates to the same tool route and surfaces the error flag in args.
//
// The router is exercised against a real MaterialApp wired to
// AppRouter.navigatorKey and a stub route table (the production screens need
// platform resolvers, so the routing contract is tested in isolation here while
// the wifi/cellular screen tests cover the on-screen states). A controllable
// stream stands in for the native trigger-event channel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/router/shortcut_deep_link_router.dart';
import 'package:wlan_pros_toolbox/services/network/shortcut_trigger_result.dart';

/// A stub tool screen that records the deep-link args it was reached with and
/// renders a marker so navigation is observable.
class _StubTool extends StatelessWidget {
  const _StubTool({required this.marker});
  final String marker;

  @override
  Widget build(BuildContext context) {
    final Object? args = ModalRoute.of(context)?.settings.arguments;
    final bool err = args is ShortcutTriggerArgs && args.initialError;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(marker),
            if (err) const Text('ERR_BANNER'),
          ],
        ),
      ),
    );
  }
}

void main() {
  group('ShortcutTriggerEvent.fromNative (wire decode)', () {
    test('parses tool + ok', () {
      final e = ShortcutTriggerEvent.fromNative('wifi-info|ok');
      expect(e.tool, 'wifi-info');
      expect(e.result, ShortcutTriggerResult.success);
    });

    test('parses tool + err', () {
      final e = ShortcutTriggerEvent.fromNative('cellular-info|err');
      expect(e.tool, 'cellular-info');
      expect(e.result, ShortcutTriggerResult.error);
    });

    test('empty tool segment decodes to a tool-less success', () {
      final e = ShortcutTriggerEvent.fromNative('|ok');
      expect(e.tool, isNull);
      expect(e.result, ShortcutTriggerResult.success);
    });

    test('no separator falls back to a bare status token', () {
      final e = ShortcutTriggerEvent.fromNative('err');
      expect(e.tool, isNull);
      expect(e.result, ShortcutTriggerResult.error);
    });
  });

  group('AppRouter.routeForTriggerTool', () {
    test('resolves the two Shortcut-backed tools to their routes', () {
      expect(AppRouter.routeForTriggerTool('wifi-info'), AppRouter.wifiInfo);
      expect(
        AppRouter.routeForTriggerTool('cellular-info'),
        AppRouter.cellularInfo,
      );
    });

    test('unknown tool id resolves to null (router no-ops)', () {
      expect(AppRouter.routeForTriggerTool('fspl'), isNull);
      expect(AppRouter.routeForTriggerTool('nope'), isNull);
    });
  });

  group('ShortcutDeepLinkRouter — cold-launch deep link', () {
    // A stub route table keyed on the SAME route names the production app uses,
    // so the router's AppRouter.routeForTriggerTool → pushNamed path is exact.
    Widget app(Stream<ShortcutTriggerEvent> wifi) => MaterialApp(
          navigatorKey: AppRouter.navigatorKey,
          initialRoute: AppRouter.home,
          routes: <String, WidgetBuilder>{
            AppRouter.home: (_) =>
                const Scaffold(body: Center(child: Text('HOME'))),
            AppRouter.wifiInfo: (_) => const _StubTool(marker: 'WIFI_TOOL'),
            AppRouter.cellularInfo: (_) =>
                const _StubTool(marker: 'CELL_TOOL'),
          },
          builder: (context, child) => ShortcutDeepLinkRouter(
            wifiEvents: wifi,
            cellularEvents: const Stream<ShortcutTriggerEvent>.empty(),
            child: child!,
          ),
        );

    testWidgets('status=ok routes to the originating tool screen',
        (tester) async {
      final controller = StreamController<ShortcutTriggerEvent>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(app(controller.stream));
      await tester.pumpAndSettle();
      // App opens to home as usual (no deep-link arrived yet).
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('WIFI_TOOL'), findsNothing);

      // Simulate the cold-launch callback being flushed once the router listens.
      controller.add(
        const ShortcutTriggerEvent(
          tool: 'wifi-info',
          result: ShortcutTriggerResult.success,
        ),
      );
      await tester.pumpAndSettle();

      // Deep-linked to the Wi-Fi tool screen, NOT left on home. No error banner.
      expect(find.text('WIFI_TOOL'), findsOneWidget);
      expect(find.text('ERR_BANNER'), findsNothing);
    });

    testWidgets('status=err routes to the tool screen and flags the error',
        (tester) async {
      final controller = StreamController<ShortcutTriggerEvent>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(app(controller.stream));
      await tester.pumpAndSettle();

      controller.add(
        const ShortcutTriggerEvent(
          tool: 'wifi-info',
          result: ShortcutTriggerResult.error,
        ),
      );
      await tester.pumpAndSettle();

      // The error routes to the SAME tool screen (not home) and the screen
      // receives ShortcutTriggerArgs(initialError: true) so it can show its
      // honest error banner there.
      expect(find.text('WIFI_TOOL'), findsOneWidget);
      expect(find.text('ERR_BANNER'), findsOneWidget);
    });

    testWidgets('tool-less return is a no-op (stays on home)', (tester) async {
      final controller = StreamController<ShortcutTriggerEvent>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(app(controller.stream));
      await tester.pumpAndSettle();

      controller.add(
        const ShortcutTriggerEvent(
          tool: null,
          result: ShortcutTriggerResult.success,
        ),
      );
      await tester.pumpAndSettle();

      // No tool id → the router does not navigate; the listening screen would
      // refresh itself in place. Here, home is untouched.
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('WIFI_TOOL'), findsNothing);
    });

    testWidgets('unknown tool id is a no-op (stays on home)', (tester) async {
      final controller = StreamController<ShortcutTriggerEvent>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(app(controller.stream));
      await tester.pumpAndSettle();

      controller.add(
        const ShortcutTriggerEvent(
          tool: 'totally-unknown',
          result: ShortcutTriggerResult.success,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
