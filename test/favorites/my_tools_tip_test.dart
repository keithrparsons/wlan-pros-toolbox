// The one-time My Tools tip (Keith, 2026-10-04, SPEC 6): after 3 tool opens
// with My Tools still empty, one SnackBar, "Press and hold any tool to add it
// to My Tools.", and never again on that device, across restarts. Not shown
// when the user already has favorites. Wording by platform (SPEC 7): press
// and hold on iOS and Android, right-click on Mac, Windows, Linux and the web.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/favorites/my_tools_controller.dart';
import 'package:wlan_pros_toolbox/favorites/my_tools_tip.dart';

final List<ToolEntry> _tools = <ToolEntry>[
  for (final ToolCategory c in kToolCategories) ...c.tools,
];

// flutter_test runs as Android unless a test overrides the platform.
const String _tip = 'Press and hold any tool to add it to My Tools.';
const String _desktopTip = 'Right-click any tool to add it to My Tools.';

/// A fresh controller pair loaded from the (mock) prefs, the way main() builds
/// them at launch. Calling it again simulates a restart.
Future<MyToolsTipController> _launch({
  List<String> favorites = const [],
}) async {
  final MyToolsController myTools = MyToolsController(initial: favorites);
  await myTools.load();
  final MyToolsTipController tip = MyToolsTipController(myTools: myTools);
  await tip.load();
  return tip;
}

/// A tiny app with the tip observer on its Navigator and a button per tool
/// that opens it by route name, as the category list does.
Future<void> _pumpApp(WidgetTester tester, MyToolsTipController tip) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: <NavigatorObserver>[tip.observer],
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: ListView(
            children: <Widget>[
              for (int i = 0; i < 5; i++)
                TextButton(
                  key: ValueKey<String>('open$i'),
                  onPressed: () =>
                      Navigator.of(context).pushNamed(_tools[i].routeName),
                  child: Text(_tools[i].title),
                ),
              TextButton(
                key: const ValueKey<String>('settings'),
                onPressed: () => Navigator.of(context).pushNamed('/settings'),
                child: const Text('Settings'),
              ),
            ],
          ),
        ),
      ),
      onGenerateRoute: (RouteSettings s) => MaterialPageRoute<void>(
        settings: s,
        builder: (_) =>
            Scaffold(appBar: AppBar(), body: Text('route:${s.name}')),
      ),
    ),
  );
}

/// Taps the button [key], lets the tip (if any) appear, and comes back home.
/// Returns whether the tip showed.
Future<bool> _openAndReturn(
  WidgetTester tester,
  String key, {
  String tip = _tip,
}) async {
  await tester.tap(find.byKey(ValueKey<String>(key)));
  await tester.pumpAndSettle();
  final bool tipShown = find.text(tip).evaluate().isNotEmpty;
  // Clear any SnackBar so it cannot carry over to the next open.
  ScaffoldMessenger.of(
    tester.element(find.byType(Scaffold).last),
  ).removeCurrentSnackBar();
  await tester.pageBack();
  await tester.pumpAndSettle();
  return tipShown;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('MyToolsTipController', () {
    test('tip is due on the 3rd open with an empty list, once', () async {
      final MyToolsTipController tip = await _launch();
      expect(await tip.recordToolOpen(), isFalse);
      expect(await tip.recordToolOpen(), isFalse);
      expect(await tip.recordToolOpen(), isTrue);
      expect(tip.shown, isTrue);
      expect(await tip.recordToolOpen(), isFalse);
      expect(await tip.recordToolOpen(), isFalse);
    });

    test('never due while the user has favorites', () async {
      final MyToolsTipController tip = await _launch(
        favorites: <String>[_tools[0].id],
      );
      for (int i = 0; i < 6; i++) {
        expect(await tip.recordToolOpen(), isFalse, reason: 'open ${i + 1}');
      }
      expect(tip.shown, isFalse);
    });

    test('the count persists across a restart', () async {
      final MyToolsTipController first = await _launch();
      expect(await first.recordToolOpen(), isFalse);
      expect(await first.recordToolOpen(), isFalse);

      final MyToolsTipController second = await _launch();
      expect(second.opens, 2);
      expect(await second.recordToolOpen(), isTrue);
    });

    test('never due again after a restart once shown', () async {
      final MyToolsTipController first = await _launch();
      for (int i = 0; i < 3; i++) {
        await first.recordToolOpen();
      }
      expect(first.shown, isTrue);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(MyToolsTipController.shownKey), isTrue);

      final MyToolsTipController second = await _launch();
      expect(second.shown, isTrue);
      for (int i = 0; i < 5; i++) {
        expect(await second.recordToolOpen(), isFalse);
      }
    });

    test('only catalog tool routes count', () {
      final MyToolsTipController tip = MyToolsTipController(
        myTools: MyToolsController(),
      );
      expect(tip.isToolRoute(_tools[0].routeName), isTrue);
      expect(tip.isToolRoute('/settings'), isFalse);
      expect(tip.isToolRoute('/'), isFalse);
      expect(tip.isToolRoute(null), isFalse);
    });
  });

  group('tip in the app', () {
    testWidgets('one SnackBar on the 3rd tool open, with an empty list, and '
        'not on later opens', (WidgetTester tester) async {
      final MyToolsTipController tip = await _launch();
      await _pumpApp(tester, tip);

      expect(await _openAndReturn(tester, 'open0'), isFalse);
      // A non-tool route does not count.
      expect(await _openAndReturn(tester, 'settings'), isFalse);
      expect(await _openAndReturn(tester, 'open1'), isFalse);
      expect(await _openAndReturn(tester, 'open0'), isTrue);
      expect(await _openAndReturn(tester, 'open2'), isFalse);
      expect(await _openAndReturn(tester, 'open3'), isFalse);
    });

    testWidgets('not shown when the user already has favorites', (
      WidgetTester tester,
    ) async {
      final MyToolsTipController tip = await _launch(
        favorites: <String>[_tools[4].id],
      );
      await _pumpApp(tester, tip);
      for (int i = 0; i < 4; i++) {
        expect(await _openAndReturn(tester, 'open$i'), isFalse);
      }
    });

    testWidgets('not shown twice across a simulated restart', (
      WidgetTester tester,
    ) async {
      MyToolsTipController tip = await _launch();
      await _pumpApp(tester, tip);
      expect(await _openAndReturn(tester, 'open0'), isFalse);
      expect(await _openAndReturn(tester, 'open1'), isFalse);
      expect(await _openAndReturn(tester, 'open2'), isTrue);

      // Restart: new controllers loaded from the same stored prefs.
      await tester.pumpWidget(const SizedBox.shrink());
      tip = await _launch();
      await _pumpApp(tester, tip);
      for (int i = 0; i < 4; i++) {
        expect(await _openAndReturn(tester, 'open$i'), isFalse);
      }
    });

    testWidgets('a restart mid-count keeps the count: tip on the 3rd open '
        'overall', (WidgetTester tester) async {
      MyToolsTipController tip = await _launch();
      await _pumpApp(tester, tip);
      expect(await _openAndReturn(tester, 'open0'), isFalse);
      expect(await _openAndReturn(tester, 'open1'), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      tip = await _launch();
      await _pumpApp(tester, tip);
      expect(await _openAndReturn(tester, 'open2'), isTrue);
    });
  });

  group('tip wording by platform (SPEC 7)', () {
    test('press and hold on iOS and Android, right-click on Mac, Windows '
        'and Linux', () {
      for (final TargetPlatform p in <TargetPlatform>[
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        expect(
          MyToolsTipController.messageFor(p, web: false),
          _tip,
          reason: '$p',
        );
      }
      for (final TargetPlatform p in <TargetPlatform>[
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          MyToolsTipController.messageFor(p, web: false),
          _desktopTip,
          reason: '$p',
        );
      }
    });

    test(
      'the web always gets the desktop wording, even on a phone browser',
      () {
        for (final TargetPlatform p in TargetPlatform.values) {
          expect(
            MyToolsTipController.messageFor(p, web: true),
            _desktopTip,
            reason: '$p',
          );
        }
      },
    );

    testWidgets(
      'the SnackBar says press and hold on phones and tablets',
      (WidgetTester tester) async {
        final MyToolsTipController tip = await _launch();
        await _pumpApp(tester, tip);
        expect(await _openAndReturn(tester, 'open0'), isFalse);
        expect(await _openAndReturn(tester, 'open1'), isFalse);
        expect(await _openAndReturn(tester, 'open2'), isTrue);
        expect(find.text(_desktopTip), findsNothing);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );

    testWidgets(
      'the SnackBar says right-click on Mac, Windows and Linux',
      (WidgetTester tester) async {
        final MyToolsTipController tip = await _launch();
        await _pumpApp(tester, tip);
        expect(
          await _openAndReturn(tester, 'open0', tip: _desktopTip),
          isFalse,
        );
        expect(
          await _openAndReturn(tester, 'open1', tip: _desktopTip),
          isFalse,
        );
        expect(await _openAndReturn(tester, 'open2', tip: _desktopTip), isTrue);
        expect(find.text(_tip), findsNothing);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );
  });
}
