// Widget tests for the Airtime Fairness screen (Wi-Fi Lab spec 04).
//
// The model has its own tests (test/services/wifi_lab/); these check the
// screen: spec defaults and the live takeaway, the Packet / Airtime / Compare
// switch, the custom-rate error state, the client-count limits, reduced
// motion, the stage / controls split, and phone width in both themes with no
// sideways scroll.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_fairness_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_fairness_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_fairness_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_fairness_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

Widget _host({ThemeData? theme, bool reducedMotion = false}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  home: Builder(
    builder: (BuildContext context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
      child: const AirtimeFairnessScreen(),
    ),
  ),
);

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _takeaway(WidgetTester tester) => tester
    .widget<Text>(find.textContaining('Packet fairness: client').first)
    .data!;

/// Choose [value] in the rate select for [label]. The menu is lazily built
/// and scrolls past five rows, so drive the select's own callback: AppSelect
/// has its own tests, this one tests what the screen does with the choice.
Future<void> _chooseRate(
  WidgetTester tester,
  String label,
  RatePreset? value,
) async {
  final AppSelect<RatePreset?> select = tester.widget<AppSelect<RatePreset?>>(
    find.byWidgetPredicate(
      (Widget w) => w is AppSelect<RatePreset?> && w.semanticLabel == label,
    ),
  );
  expect(
    select.items.map((AppSelectItem<RatePreset?> i) => i.$1),
    contains(value),
  );
  select.onChanged(value);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('spec defaults: 4 clients, compare view, live takeaway', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Airtime Fairness'), findsOneWidget);
    expect(find.text('Clients (4 of 8)'), findsOneWidget);
    final String line = _takeaway(tester);
    expect(line, contains('client D (6 Mbps) holds 53% of the air'));
    expect(line, contains('client A (867 Mbps) gets 92.0 Mbps'));
    expect(line, contains('gets 147.4 Mbps'));
    expect(line, contains('rises from 278.9 to 443.4 Mbps'));
    // Both rules drawn: two share bars, two round lanes.
    expect(find.text('Packet fairness'), findsNWidgets(2));
    expect(find.text('Airtime fairness'), findsNWidgets(2));
    // The teaching-model statement and the pointer to Airtime Anatomy.
    expect(find.textContaining('This is a teaching model'), findsOneWidget);
    expect(find.textContaining('Airtime Anatomy'), findsOneWidget);
  });

  testWidgets('stage and controls are separate widgets', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.byType(AirtimeFairnessStage), findsOneWidget);
    expect(find.byType(AirtimeFairnessRuleCard), findsOneWidget);
    expect(find.byType(AirtimeFairnessClientsCard), findsOneWidget);
    // No control lives inside the stage.
    for (final Type t in <Type>[AppSelect<int>, TextField, OutlinedButton]) {
      expect(
        find.descendant(
          of: find.byType(AirtimeFairnessStage),
          matching: find.byType(t),
        ),
        findsNothing,
      );
    }
  });

  testWidgets('switching to Packet shows one rule and a packet takeaway', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Packet').first);
    await tester.pumpAndSettle();
    expect(find.text('Airtime fairness'), findsNothing);
    expect(find.text('Packet fairness'), findsNWidgets(2));
    expect(_takeaway(tester), endsWith('Total 278.9 Mbps.'));

    await tester.tap(find.text('Airtime').first);
    await tester.pumpAndSettle();
    expect(find.text('Packet fairness'), findsNothing);
    expect(
      find.textContaining('Airtime fairness: 25% of the air each'),
      findsOneWidget,
    );
  });

  testWidgets('custom rate: empty is an error state, a valid rate recovers', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 5000));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // Client D's PHY-rate select reads "6 Mbps (Legacy)".
    await _chooseRate(tester, 'Client D PHY rate', null);
    final Finder field = find.byType(TextField);
    expect(field, findsOneWidget);
    // Seeded from the preset being left.
    expect(tester.widget<TextField>(field).controller!.text, '6');

    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(find.text('Enter a rate in Mbps'), findsOneWidget);
    expect(find.textContaining('Client D needs a PHY rate'), findsOneWidget);
    expect(find.textContaining('Packet fairness: client'), findsNothing);

    await tester.enterText(field, '20000');
    await tester.pumpAndSettle();
    expect(find.text('Use 1 to 10,000 Mbps'), findsOneWidget);

    await tester.enterText(field, '6');
    await tester.pumpAndSettle();
    expect(find.textContaining('Client D needs a PHY rate'), findsNothing);
    expect(_takeaway(tester), contains('holds 53% of the air'));
  });

  testWidgets('clients: add stops at 8, remove stops at 1', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 9000));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    for (int i = 4; i < 8; i++) {
      await tester.ensureVisible(find.text('Add client'));
      await tester.tap(find.text('Add client'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Clients (8 of 8)'), findsOneWidget);
    final OutlinedButton add = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Add client'),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );
    expect(add.onPressed, isNull);

    for (int i = 8; i > 1; i--) {
      final Finder remove = find.byTooltip('Remove client A');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
    }
    expect(find.text('Clients (1 of 8)'), findsOneWidget);
    expect(find.byTooltip('At least one client is required'), findsOneWidget);
    expect(
      find.textContaining('One client has the air to itself'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a legacy client cannot aggregate', (WidgetTester tester) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    final Iterable<AppSelect<int>> aggregation = tester
        .widgetList<AppSelect<int>>(find.byType(AppSelect<int>))
        .where(
          (AppSelect<int> s) =>
              s.semanticLabel!.contains('aggregation') ||
              s.semanticLabel!.contains('frames per turn'),
        );
    expect(aggregation, hasLength(4));
    expect(aggregation.map((AppSelect<int> s) => s.enabled), <bool>[
      true,
      true,
      true,
      false,
    ]);
  });

  testWidgets('reduced motion: round drawn complete, no Replay button', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host(reducedMotion: true));
    await tester.pump();
    expect(find.textContaining('Reduced motion is on'), findsOneWidget);
    expect(find.text('Replay round'), findsNothing);
    // Nothing is animating: no frames are scheduled.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Replay runs the round and it settles', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Replay round'));
    await tester.tap(find.text('Replay round'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final (String name, ThemeData Function() theme) variant
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    testWidgets('${variant.$1}: 390 px lays out with no sideways scroll', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, const Size(390, 5000));
      await tester.pumpWidget(_host(theme: variant.$2()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final Iterable<Scrollable> horizontal = tester
          .widgetList<Scrollable>(find.byType(Scrollable))
          .where(
            (Scrollable s) =>
                s.axisDirection == AxisDirection.right ||
                s.axisDirection == AxisDirection.left,
          );
      expect(horizontal, isEmpty);
    });
  }
}
