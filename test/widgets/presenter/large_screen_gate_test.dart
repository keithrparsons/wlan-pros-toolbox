// The Wi-Fi Classroom large-screen notice (Keith, 2026-09-26: "Go with the
// large-screen notice and Continue anyway").
//
// Pins: the notice shows below the presenter threshold and not at or above
// it; Continue anyway reveals the tool and is remembered for the session;
// Go back leaves; a window that grows or shrinks across the threshold never
// swaps a shown tool back; a non-Lab tool is never gated; every Lab catalog
// tool is gated through the router; every Lab help entry says the Lab is
// designed for tablets and computers.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

import 'presenter_test_support.dart';

const String _labA = '/test/lab-a';
const String _labB = '/test/lab-b';
const String _plain = '/test/plain';

const String _handout = '/test/handout';

/// A two-simulator Classroom plus a Classroom handout and one ordinary tool, so
/// the gate's behavior is tested without pumping a real simulator.
final List<ToolCategory> _fakeCatalog = <ToolCategory>[
  ToolCategory(
    id: kWifiClassroomCategoryId,
    title: 'Test',
    summary: '',
    icon: Icons.science,
    exampleToolTitles: const <String>[],
    tools: const <ToolEntry>[
      ToolEntry(
        id: 'lab-a',
        title: 'Lab A',
        description: '',
        routeName: _labA,
        isLive: true,
        subgroup: 'Signals and PHY',
      ),
      ToolEntry(
        id: 'lab-b',
        title: 'Lab B',
        description: '',
        routeName: _labB,
        isLive: true,
        subgroup: 'Signals and PHY',
      ),
      ToolEntry(
        id: 'handout',
        title: 'Handout',
        description: '',
        routeName: _handout,
        isLive: true,
        subgroup: 'Course Handouts',
      ),
    ],
  ),
  ToolCategory(
    id: 'other',
    title: 'Other',
    summary: '',
    icon: Icons.science,
    exampleToolTitles: const <String>[],
    tools: const <ToolEntry>[
      ToolEntry(
        id: 'plain',
        title: 'Plain',
        description: '',
        routeName: _plain,
        isLive: true,
        // A simulator shelf name OUTSIDE the Classroom must not be gated.
        subgroup: 'Signals and PHY',
      ),
    ],
  ),
];

Widget _tool(String label) => Scaffold(
  appBar: AppBar(title: Text(label)),
  body: Text('$label body'),
);

final Map<String, WidgetBuilder> _routes =
    gateWifiLabRoutes(<String, WidgetBuilder>{
      '/': (_) => const _Home(),
      _labA: (_) => _tool('Lab A'),
      _labB: (_) => _tool('Lab B'),
      _plain: (_) => _tool('Plain'),
      _handout: (_) => _tool('Handout'),
    }, catalog: _fakeCatalog);

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        const Text('Home'),
        for (final String r in <String>[_labA, _labB, _plain, _handout])
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed(r),
            child: Text('open $r'),
          ),
      ],
    ),
  );
}

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  setWindow(tester, size);
  resetLargeScreenNoticeForTest();
  addTearDown(resetLargeScreenNoticeForTest);
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark(), routes: _routes, initialRoute: '/'),
  );
}

Future<void> _open(WidgetTester tester, String route) async {
  await tester.tap(find.text('open $route'));
  await tester.pumpAndSettle();
}

final Finder _notice = find.text(kLargeScreenNoticeTitle);

void main() {
  group('threshold (the Present button\'s)', () {
    for (final Size size in const <Size>[Size(390, 844), Size(480, 320)]) {
      testWidgets('notice shows at ${size.width}x${size.height}', (
        WidgetTester tester,
      ) async {
        await _pumpApp(tester, size);
        await _open(tester, _labA);
        expect(_notice, findsOneWidget);
        expect(find.text(kLargeScreenNoticeBody), findsOneWidget);
        expect(find.text(kLargeScreenContinueLabel), findsOneWidget);
        expect(find.text(kLargeScreenBackLabel), findsOneWidget);
        expect(find.text('Lab A body'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final Size size in const <Size>[Size(800, 600), Size(1470, 923)]) {
      testWidgets('no notice at ${size.width}x${size.height}', (
        WidgetTester tester,
      ) async {
        await _pumpApp(tester, size);
        await _open(tester, _labA);
        expect(_notice, findsNothing);
        expect(find.text('Lab A body'), findsOneWidget);
      });
    }
  });

  testWidgets('Continue anyway reveals the tool and is remembered for the '
      'session', (WidgetTester tester) async {
    await _pumpApp(tester, const Size(390, 844));
    await _open(tester, _labA);
    await tester.tap(find.text(kLargeScreenContinueLabel));
    await tester.pumpAndSettle();
    expect(_notice, findsNothing);
    expect(find.text('Lab A body'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _open(tester, _labB);
    expect(_notice, findsNothing);
    expect(find.text('Lab B body'), findsOneWidget);
  });

  testWidgets('Go back returns to where the user came from', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, const Size(390, 844));
    await _open(tester, _labA);
    await tester.tap(find.text(kLargeScreenBackLabel));
    await tester.pumpAndSettle();
    expect(_notice, findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(largeScreenNoticeDismissed.value, isFalse);

    // Not dismissed, so the next Lab tool asks again.
    await _open(tester, _labB);
    expect(_notice, findsOneWidget);
  });

  testWidgets('a notice gives way when the window grows past the threshold', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, const Size(480, 320));
    await _open(tester, _labA);
    expect(_notice, findsOneWidget);
    setWindow(tester, const Size(800, 600));
    await tester.pumpAndSettle();
    expect(_notice, findsNothing);
    expect(find.text('Lab A body'), findsOneWidget);
  });

  testWidgets('a shown tool stays when the window shrinks or a phone rotates', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, const Size(800, 600));
    await _open(tester, _labA);
    for (final Size s in const <Size>[Size(390, 844), Size(844, 390)]) {
      setWindow(tester, s);
      await tester.pumpAndSettle();
      expect(_notice, findsNothing, reason: '$s');
      expect(find.text('Lab A body'), findsOneWidget, reason: '$s');
    }
  });

  testWidgets('a non-Lab tool never shows the notice', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, const Size(390, 844));
    await _open(tester, _plain);
    expect(_notice, findsNothing);
    expect(find.text('Plain body'), findsOneWidget);
  });

  testWidgets('a Classroom handout on a phone opens with no notice', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, const Size(390, 844));
    await _open(tester, _handout);
    expect(_notice, findsNothing);
    expect(find.text('Handout body'), findsOneWidget);
  });

  testWidgets('notice renders without overflow in light mode at 390x844', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LargeScreenNotice(
          toolTitle: 'Lab A',
          onContinue: () {},
          onBack: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(_notice, findsOneWidget);
  });

  group('the real router', () {
    late BuildContext ctx;

    Future<void> grabContext(WidgetTester tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
    }

    testWidgets('every Wi-Fi Classroom catalog tool is gated', (
      WidgetTester tester,
    ) async {
      await grabContext(tester);
      final List<ToolEntry> lab = wifiLabTools().toList();
      expect(lab.length, greaterThanOrEqualTo(23));
      for (final ToolEntry t in lab) {
        final WidgetBuilder? b = AppRouter.routes[t.routeName];
        expect(b, isNotNull, reason: '${t.id} has no route');
        final Widget w = b!(ctx);
        expect(w, isA<LargeScreenGate>(), reason: t.id);
        expect((w as LargeScreenGate).toolTitle, t.title);
      }
    });

    testWidgets('no tool outside the Classroom simulators is gated, lessons '
        'and handouts included', (WidgetTester tester) async {
      await grabContext(tester);
      final Set<String> labRoutes = <String>{
        for (final ToolEntry t in wifiLabTools()) t.routeName,
      };
      int checked = 0;
      for (final ToolCategory c in kToolCategories) {
        for (final ToolEntry t in c.tools) {
          if (labRoutes.contains(t.routeName)) continue;
          final WidgetBuilder? b = AppRouter.routes[t.routeName];
          if (b == null) continue;
          expect(b(ctx), isNot(isA<LargeScreenGate>()), reason: t.id);
          checked++;
        }
      }
      expect(checked, greaterThan(0));
    });
  });

  group(
    'simulators only (Keith, 2026-09-26: lessons and handouts moved in)',
    () {
      test('gating is by Classroom simulator shelf, not by category alone', () {
        final Set<String> gated = <String>{
          for (final ToolEntry t in wifiLabTools(_fakeCatalog)) t.id,
        };
        expect(gated, <String>{'lab-a', 'lab-b'});
      });

      test('every Classroom shelf is classified as gated or ungated, once', () {
        final Set<String> shelves = <String>{
          for (final ToolEntry t
              in kToolCategories
                  .firstWhere(
                    (ToolCategory c) => c.id == kWifiClassroomCategoryId,
                  )
                  .tools)
            t.subgroup!,
        };
        expect(
          kWifiClassroomSimulatorSubgroups.intersection(
            kWifiClassroomUngatedSubgroups,
          ),
          isEmpty,
        );
        expect(
          shelves,
          kWifiClassroomSimulatorSubgroups.union(
            kWifiClassroomUngatedSubgroups,
          ),
          reason:
              'a new Classroom shelf must be added to exactly one of the two '
              'sets in large_screen_gate.dart before it ships',
        );
      });

      test('exactly the 24 simulators are gated in the real catalog', () {
        final List<ToolEntry> lab = wifiLabTools().toList();
        expect(lab, hasLength(24));
      });
    },
  );

  test('every Wi-Fi Classroom help entry says the Lab is for tablets and '
      'computers', () {
    final Map<String, dynamic> tools =
        (jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>;
    for (final ToolEntry t in wifiLabTools()) {
      final Map<String, dynamic>? entry = tools[t.id] as Map<String, dynamic>?;
      expect(entry, isNotNull, reason: t.id);
      final List<dynamic> notes = entry!['fieldNotes'] as List<dynamic>;
      expect(
        notes.any(
          (dynamic n) => (n as String).contains(
            'The Wi-Fi Classroom is designed for tablets and computers',
          ),
        ),
        isTrue,
        reason: t.id,
      );
    }
  });
}
