// Widget tests for the Wi-Fi Classroom "Legacy Protection Cost" screen
// (legacy-protection). The math has its own tests (test/services/wifi_lab/
// legacy_protection_model_test.dart); these check the screen: it opens on
// the spec defaults, the toggles move the ERP bits and the readouts, 1 Mb/s
// short preamble is grayed out with its reason, predict-then-reveal hides
// and shows the answer, the labeled defaults say so, Play sweeps, and the
// layout holds at phone widths in both themes with no sideways scrolling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/legacy_protection_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/legacy_protection_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/legacy_protection_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/dsss_timing.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/legacy_protection_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<LegacyProtectionController> _open(
  WidgetTester tester, {
  Size size = const Size(800, 5200),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final LegacyProtectionController c = LegacyProtectionController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: LegacyProtectionScreen(controller: c),
    ),
  );
  await tester.pump();
  return c;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

void main() {
  test('catalog registers legacy-protection in Wi-Fi Classroom, with its '
      'route', () {
    final ToolCategory cat = kToolCategories.firstWhere(
      (ToolCategory c) =>
          c.tools.any((ToolEntry e) => e.id == 'legacy-protection'),
    );
    expect(cat.id, 'wifi-classroom');
    final ToolEntry t = cat.tools.firstWhere(
      (ToolEntry e) => e.id == 'legacy-protection',
    );
    expect(t.title, 'Legacy Protection Cost');
    expect(t.subgroup, 'Airtime and Access');
    expect(t.routeName, '/tools/legacy-protection');
    expect(AppRouter.legacyProtection, t.routeName);
    expect(kLegacyProtectionToolId, t.id);
  });

  testWidgets('opens on the defaults: associated, CTS-to-self at 1 Mb/s long, '
      '30.5 falls to 14.8 Mb/s', (WidgetTester tester) async {
    await _open(tester);
    expect(find.text('Legacy Protection Cost'), findsOneWidget);
    expect(find.byType(LegacyProtectionStage), findsOneWidget);
    expect(find.byType(LegacyProtectionControls), findsOneWidget);
    expect(find.text('14.8 Mb/s'), findsWidgets);
    expect(find.text('51.5%'), findsWidgets);
    expect(find.textContaining('30.5 Mb/s'), findsWidgets);
    expect(find.text('812 µs'), findsWidgets);
    expect(find.text('393.5 µs'), findsWidgets);
    // The protection frame and the slot, each its own readout.
    expect(find.text('314 µs'), findsWidgets);
    expect(find.text('104.5 µs'), findsOneWidget);
    // The ceiling table marks the row this network is on.
    expect(
      find.text('Long slot + CTS-to-self at 1 Mb/s long (this network)'),
      findsOneWidget,
    );
  });

  testWidgets('labeled defaults and sources say so', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    expect(
      find.textContaining('A provisional default, not yet confirmed'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'readout is a provisional default, not yet confirmed',
      ),
      findsOneWidget,
    );
    expect(find.text('31 (unverified)'), findsOneWidget);
    expect(find.textContaining('illustrative default'), findsOneWidget);
  });

  testWidgets('1 Mb/s short preamble is grayed out, with the reason', (
    WidgetTester tester,
  ) async {
    final LegacyProtectionController c = await _open(tester);
    expect(
      find.text(
        '1 Mb/s short: 802.11b defines short preamble only for 2, 5.5 and '
        '11 Mb/s.',
      ),
      findsOneWidget,
    );
    final Finder na = find.widgetWithText(OutlinedButton, 'n/a');
    expect(na, findsOneWidget);
    expect(tester.widget<OutlinedButton>(na).onPressed, isNull);
    // The model refuses it too.
    c.pickProtection(ProtectionRate.r1, DsssPreamble.short);
    expect(c.config.protection.preamble, DsssPreamble.long);
  });

  testWidgets('picking 11 Mb/s short moves the cycle to 615 µs', (
    WidgetTester tester,
  ) async {
    final LegacyProtectionController c = await _open(tester);
    c.oldDeviceShortPreamble = true;
    await tester.pump();
    await _tap(tester, find.widgetWithText(OutlinedButton, '117 µs'));
    expect(c.config.protection.rate, ProtectionRate.r11);
    expect(c.config.protection.preamble, DsssPreamble.short);
    expect(find.text('615 µs'), findsWidgets);
    expect(find.text('19.5 Mb/s'), findsWidgets);
  });

  testWidgets('a short-preamble frame the old device cannot decode gets a '
      'worded warning', (WidgetTester tester) async {
    final LegacyProtectionController c = await _open(tester);
    c.pickProtection(ProtectionRate.r11, DsssPreamble.short);
    await tester.pump();
    expect(
      find.textContaining('could not decode this protection frame'),
      findsOneWidget,
    );
    c.oldDeviceShortPreamble = true;
    await tester.pump();
    expect(
      find.textContaining('could not decode this protection frame'),
      findsNothing,
    );
  });

  testWidgets('associated sets both bits; heard sets Use_Protection only; '
      'nothing old reads 0', (WidgetTester tester) async {
    final LegacyProtectionController c = await _open(tester);
    expect(
      find.bySemanticsLabel(RegExp(r'^NonERP_Present is 1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^HT Protection is 3')),
      findsOneWidget,
    );

    await _tap(tester, find.text('802.11b device associated'));
    expect(c.config.associated, isFalse);
    expect(
      find.bySemanticsLabel(RegExp(r'^Use_Protection is 0')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^HT Protection is 0')),
      findsOneWidget,
    );
    expect(find.text('0.0%'), findsWidgets);

    await _tap(tester, find.text('802.11b network heard nearby'));
    expect(
      find.bySemanticsLabel(RegExp(r'^NonERP_Present is 0')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Use_Protection is 1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^HT Protection is 1')),
      findsOneWidget,
    );
    // The disagreement label, word for word.
    expect(find.text(kLpSourcesDisagree), findsOneWidget);
    // Heard never forces the long slot.
    expect(c.result.cycle.spec.slotUs, 9);
  });

  testWidgets('predict, then reveal hides the answer until Reveal', (
    WidgetTester tester,
  ) async {
    final LegacyProtectionController c = await _open(tester);
    c.associated = false;
    await tester.pump();
    await _tap(tester, find.text('Ask the class'));
    expect(c.config, const LpConfig());
    expect(find.text('51.5%'), findsNothing);
    expect(find.text('14.8 Mb/s'), findsNothing);
    expect(find.text('?'), findsWidgets);
    await _tap(tester, find.text('40 to 60%'));
    await _tap(tester, find.text('Reveal'));
    expect(find.text('51.5%'), findsWidgets);
    expect(
      find.text(
        'It costs 51.5%, about half: the laptop falls from 30.5 Mb/s to '
        '14.8 Mb/s.',
      ),
      findsOneWidget,
    );
    expect(find.text('The class picked 40 to 60%: right.'), findsOneWidget);
    await _tap(tester, find.text('Done'));
    expect(find.text('Ask the class'), findsOneWidget);
    await tester.pump(kLpSweepDuration);
    await tester.pump();
  });

  testWidgets('Play sweeps; Next cycle and Reset move the playhead', (
    WidgetTester tester,
  ) async {
    final LegacyProtectionController c = await _open(tester);
    expect(c.playhead.value, 1);
    await _tap(tester, find.text('Play'));
    expect(c.playing, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(c.playhead.value, closeTo(0.5, 0.02));
    await tester.pump(const Duration(seconds: 4));
    expect(c.playing, isFalse);
    expect(c.playhead.value, 1);
    await _tap(tester, find.text('Reset'));
    expect(c.playhead.value, 0);
    await _tap(tester, find.text('Next cycle'));
    // One 812 us cycle of a 3 ms window.
    expect(c.playhead.value, closeTo(812 / 3000, 1e-9));
  });

  testWidgets('with reduced motion, Reveal draws the window whole', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 5200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final LegacyProtectionController c = LegacyProtectionController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: LegacyProtectionScreen(controller: c),
        ),
      ),
    );
    await tester.pump();
    c.ask();
    c.reveal();
    await tester.pump();
    expect(c.playing, isFalse);
    expect(c.playhead.value, 1);
  });

  testWidgets('copy text carries the bits and the numbers', (
    WidgetTester tester,
  ) async {
    final LegacyProtectionController c = await _open(tester);
    final String t = c.copyText();
    expect(t, contains('NonERP_Present 1, Use_Protection 1'));
    expect(t, contains('HT (High Throughput) Protection: 3'));
    expect(t, contains('14.8 Mb/s'));
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double width in <double>[320, 390, 1024]) {
      testWidgets('$name: ${width.toInt()} px lays out with no overflow', (
        WidgetTester tester,
      ) async {
        final LegacyProtectionController c = await _open(
          tester,
          size: Size(width, 7000),
          theme: theme(),
        );
        c.heard = true;
        c.cwMin = LpCwMin.cw31;
        c.protectionKind = ProtectionKind.rtsCts;
        c.pickProtection(ProtectionRate.r5_5, DsssPreamble.short);
        await tester.pump();
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
}
