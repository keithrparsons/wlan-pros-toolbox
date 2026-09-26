// Widget tests for OFDMA Resource Units (Wi-Fi Classroom).
//
// The math has its own tests (test/services/wifi_lab/ofdma_model_test.dart);
// these check the screen: it opens on the research brief's worked example,
// stage and controls are separate widgets over one model, clients move by
// tap-then-target and by drag, a set that does not fit is not drawn and says
// why, estimates are labeled, and the layout holds at phone width in both
// themes without sideways scrolling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_simulator_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_simulator_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_simulator_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/ofdma_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

Widget _host({ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  home: const OfdmaSimulatorScreen(),
);

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Picks [value] in the AppSelect whose semantic label is [label]. A menu of
/// 18 rows scrolls, so drive the select's own callback (as the airtime
/// fairness tests do); the tap path is the platform's DropdownButton.
Future<void> _pick<T>(WidgetTester tester, String label, T value) async {
  final AppSelect<T> select = tester.widget<AppSelect<T>>(
    find.byWidgetPredicate(
      (Widget w) => w is AppSelect<T> && w.semanticLabel == label,
    ),
  );
  expect(select.items.map((AppSelectItem<T> i) => i.$1), contains(value));
  select.onChanged(value);
  await tester.pumpAndSettle();
}

Finder _block(String letter) =>
    find.bySemanticsLabel(RegExp('^Client $letter, '));

void main() {
  testWidgets('opens on the worked example: 916 vs 403 vs 408 µs', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('OFDMA Resource Units'), findsOneWidget);
    expect(find.byType(OfdmaSimulatorStage), findsOneWidget);
    expect(find.byType(OfdmaSimulatorControls), findsOneWidget);
    // Totals in the stage and in the readouts.
    expect(find.text('915.6 µs'), findsOneWidget);
    expect(find.text('403.3 µs'), findsOneWidget);
    expect(find.text('408.1 µs'), findsOneWidget);
    expect(find.text('915.6'), findsOneWidget);
    expect(find.text('2.27x'), findsOneWidget);
    expect(find.text('2.24x'), findsOneWidget);
    expect(find.textContaining('DL OFDMA saves 512.3 µs'), findsOneWidget);
    expect(find.textContaining('331.5 µs of contention'), findsOneWidget);
    expect(find.textContaining('not a faster PHY'), findsOneWidget);
    for (final String l in <String>['A', 'B', 'C', 'D']) {
      expect(_block(l), findsOneWidget);
    }
  });

  testWidgets('every estimate carries an Assumption label on screen', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    for (final OfdmaAssumption a in OfdmaAssumption.values) {
      expect(find.text('Assumption: ${a.title}'), findsOneWidget);
    }
    await _tap(tester, find.text('Show the arithmetic'));
    // Now also tagged inside the working.
    expect(
      find.text('Assumption: ${OfdmaAssumption.sigB.title}'),
      findsNWidgets(2),
    );
    expect(
      find.text('Assumption: ${OfdmaAssumption.multiStaBa.title}'),
      findsNWidgets(2),
    );
    expect(find.textContaining('HE-SIG-B 5 x 4'), findsOneWidget);
  });

  testWidgets('tap a client, then a dashed outline, to move it', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    // Four 52-tone RUs fill 20 MHz, so drop to three clients to free one.
    await _pick<int>(tester, 'Clients', 3);
    expect(_block('D'), findsNothing);
    await _tap(tester, _block('A'));
    final Finder target = find.bySemanticsLabel(
      'Move A to 52-tone RU at slots 8 to 9',
    );
    expect(target, findsOneWidget);
    await _tap(tester, target);
    expect(
      find.bySemanticsLabel(RegExp('^Client A, 52-tone RU, slots 8 to 9')),
      findsOneWidget,
    );
  });

  testWidgets('drag a client along the channel', (WidgetTester tester) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await _pick<int>(tester, 'Clients', 3);
    final Finder a = _block('A');
    await tester.ensureVisible(a);
    await tester.pump();
    final Rect from = tester.getRect(a);
    // A sits on slots 1-2; the free 52-tone RU is slots 8-9, far right.
    await tester.drag(a, Offset(from.width * 3.2, 0));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('^Client A, 52-tone RU, slots 8 to 9')),
      findsOneWidget,
    );
  });

  testWidgets('a set that does not fit is not drawn and says why', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await _pick<int>(tester, 'Clients', 5);
    expect(find.textContaining('No room for E'), findsOneWidget);
    expect(
      find.text('Not drawn. These RUs do not fit in the channel.'),
      findsNWidgets(2),
    );
    expect(
      find.text('Check: These RUs do not fit in the channel'),
      findsOneWidget,
    );
    // SU still computes: five TXOPs.
    expect(find.text('1144.5 µs'), findsOneWidget);
    // Largest equal RUs fixes it: five 26-tone RUs.
    await _tap(tester, find.text('Largest equal RUs'));
    expect(find.textContaining('No room'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('^Client E, 26-tone RU')),
      findsOneWidget,
    );
  });

  testWidgets('one client on the whole channel: OFDMA gains nothing', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await _pick<int>(tester, 'Clients', 1);
    await _tap(tester, find.text('Largest equal RUs'));
    expect(
      find.bySemanticsLabel(RegExp('^Client A, 242-tone RU')),
      findsOneWidget,
    );
    expect(find.textContaining('MORE than SU'), findsOneWidget);
  });

  testWidgets('the model is shared: a stage selection drives the controls', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await _tap(tester, _block('B'));
    expect(find.text('RU size, client B'), findsOneWidget);
    final OfdmaSimulatorStage stage = tester.widget(
      find.byType(OfdmaSimulatorStage),
    );
    final OfdmaSimulatorControls controls = tester.widget(
      find.byType(OfdmaSimulatorControls),
    );
    expect(identical(stage.model, controls.model), isTrue);
    expect(stage.model.selected, 1);
    expect(stage.model, isA<OfdmaSimulatorModel>());
  });

  for (final (String name, ThemeData Function() theme) t
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    testWidgets('phone width, ${t.$1}: no overflow, no sideways scroll', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, const Size(390, 5200));
      await tester.pumpWidget(_host(theme: t.$2()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Widest case: 18 clients at 160 MHz.
      await _pick<int>(tester, 'Channel width', 160);
      await _pick<int>(tester, 'Clients', 18);
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
      for (final ScrollableState s in tester.stateList<ScrollableState>(
        find.byType(Scrollable),
      )) {
        if (s.position.axis == Axis.horizontal) {
          expect(s.position.maxScrollExtent, 0);
        }
      }
    });
  }

  // Registration. Deliberately NO neighbor assertions: several Wi-Fi Classroom tools
  // merge into one branch, so which tool sits before or after this one, and
  // whether it is last, is not this tool's contract.
  test('catalog entry: rf-calculators, subgroup Wi-Fi Classroom, live, routed', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final List<ToolEntry> hits = rf.tools
        .where((ToolEntry t) => t.id == kOfdmaSimulatorToolId)
        .toList();
    expect(hits, hasLength(1));
    final ToolEntry e = hits.single;
    expect(e.title, 'OFDMA Resource Units');
    expect(e.routeName, '/tools/ofdma-simulator');
    expect(e.subgroup, 'Wi-Fi Classroom');
    expect(e.isLive, isTrue);
    expect(AppRouter.ofdmaSimulator, e.routeName);
    expect(AppRouter.routes.containsKey(e.routeName), isTrue);
  });
}
