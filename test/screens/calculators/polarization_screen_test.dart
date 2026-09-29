// Screen tests for Polarization (spec 45, "Done means" 3): motion and reduced
// motion, the preset select, the components switch, Custom, the no-field
// state, no handedness words, the Antenna Pattern link, and the 390 px phone.
// The field animates on a clock, so these pump fixed durations rather than
// settling.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/polarization_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/polarization_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/polarization_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<PolarizationController> _open(
  WidgetTester tester, {
  bool reduceMotion = false,
  Size size = const Size(1280, 1600),
  ThemeData? theme,
}) async {
  setWindow(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: reduceMotion),
        child: const PolarizationScreen(),
      ),
    ),
  );
  await _settle(tester);
  return tester
      .widget<PolarizationStage>(find.byType(PolarizationStage))
      .controller;
}

/// Every Text on screen, joined, for word checks.
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join(' | ');

void main() {
  testWidgets('opens on Vertical, playing; Pause freezes the phase', (
    WidgetTester tester,
  ) async {
    final PolarizationController c = await _open(tester);
    expect(c.playing, isTrue);
    expect(c.preset, PolarizationPreset.vertical);
    expect(find.text('Vertical'), findsWidgets);
    expect(find.text('a line'), findsOneWidget);
    expect(find.text('infinite'), findsOneWidget);
    final double before = c.phase;
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.phase, isNot(before));

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(c.playing, isFalse);
    final double frozen = c.phase;
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.phase, frozen);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('reduced motion opens frozen, says so, and Play still works', (
    WidgetTester tester,
  ) async {
    final PolarizationController c = await _open(tester, reduceMotion: true);
    expect(c.playing, isFalse);
    expect(find.textContaining('Reduced motion is on'), findsOneWidget);
    final double frozen = c.phase;
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.phase, frozen);
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.playing, isTrue);
    expect(c.phase, isNot(frozen));
    c.setPlaying(false);
    await _settle(tester);
  });

  testWidgets('the select sets each preset and the readouts follow', (
    WidgetTester tester,
  ) async {
    final PolarizationController c = await _open(tester);
    c.setPlaying(false);
    await _settle(tester);
    await tester.tap(find.byType(AppSelect<PolarizationPreset>));
    await _settle(tester);
    await tester.tap(find.text('Circular').last);
    await _settle(tester);
    expect(c.preset, PolarizationPreset.circular);
    expect(find.text('a circle'), findsOneWidget);
    expect(find.text('1.0'), findsOneWidget);
    expect(find.text('none (a circle)'), findsOneWidget);

    c.setPreset(PolarizationPreset.elliptical);
    await _settle(tester);
    expect(find.text('an ellipse'), findsOneWidget);
    expect(find.text('2.0'), findsOneWidget);
    expect(find.text('0° (horizontal)'), findsOneWidget);

    c.setPreset(PolarizationPreset.slant45);
    await _settle(tester);
    expect(find.text('45° from horizontal'), findsOneWidget);
  });

  testWidgets('the components switch adds the H and V legend', (
    WidgetTester tester,
  ) async {
    final PolarizationController c = await _open(tester);
    c.setPlaying(false);
    await _settle(tester);
    expect(find.text('H: the horizontal part alone'), findsNothing);
    await tester.tap(find.text('Show the H and V component waves'));
    await _settle(tester);
    expect(c.showComponents, isTrue);
    expect(find.text('H: the horizontal part alone'), findsOneWidget);
    expect(find.text('V: the vertical part alone'), findsOneWidget);
  });

  testWidgets('moving a slider off every preset reads Custom; back on one '
      'reads its name', (WidgetTester tester) async {
    final PolarizationController c = await _open(tester);
    c.setPlaying(false);
    await tester.tap(find.text('Adjust: amplitudes and phase difference'));
    await _settle(tester);
    c.setField(c.state.copyWith(ax: 0.5));
    await _settle(tester);
    expect(c.preset, PolarizationPreset.custom);
    expect(find.text('Custom'), findsOneWidget);
    c.setField(const PolarizationState(ax: 1, ay: 0, deltaDeg: 0));
    await _settle(tester);
    expect(c.preset, PolarizationPreset.horizontal);
  });

  testWidgets('both amplitudes 0: the no-field state, readouts say none', (
    WidgetTester tester,
  ) async {
    final PolarizationController c = await _open(tester);
    c.setPlaying(false);
    c.setField(const PolarizationState(ax: 0, ay: 0, deltaDeg: 0));
    await _settle(tester);
    expect(find.text('No field: raise the H or V amplitude.'), findsOneWidget);
    expect(find.text('No field'), findsOneWidget);
    expect(find.text('nothing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no right-hand or left-hand wording on any preset (spec 45)', (
    WidgetTester tester,
  ) async {
    final PolarizationController c = await _open(tester);
    c.setPlaying(false);
    for (final PolarizationPreset p in PolarizationPreset.named) {
      c.setPreset(p);
      await _settle(tester);
      final String all = _allText(tester).toLowerCase();
      for (final String banned in <String>[
        'right-hand',
        'left-hand',
        'right hand',
        'left hand',
        'rhcp',
        'lhcp',
        'right circular',
        'left circular',
      ]) {
        expect(all.contains(banned), isFalse, reason: '$banned on ${p.label}');
      }
      expect(c.copyText().toLowerCase().contains('hand'), isFalse);
    }
  });

  testWidgets('the 3D viewport rotates with the arrow keys and Reset view '
      'returns it', (WidgetTester tester) async {
    final PolarizationController c = await _open(tester);
    c.setPlaying(false);
    await tester.tap(find.byType(PolarizationViewport));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(c.view.value, isNot(PolarizationController.initialView));
    await tester.tap(find.text('Reset view'));
    await tester.pump();
    expect(c.view.value, PolarizationController.initialView);
  });

  testWidgets('copy text names the preset and credits EMANIM Classic', (
    WidgetTester tester,
  ) async {
    final PolarizationController c = await _open(tester);
    c.setPlaying(false);
    c.setPreset(PolarizationPreset.circular);
    final String t = c.copyText();
    expect(t, contains('Polarization: Circular'));
    expect(t, contains('Axial ratio: 1.0'));
    expect(t, contains('EMANIM Classic by Andras Szilagyi'));
    expect(t.toLowerCase(), isNot(contains('siam')));
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    testWidgets('$name 390 px phone: fullest state, no overflow', (
      WidgetTester tester,
    ) async {
      final PolarizationController c = await _open(
        tester,
        size: const Size(390, 844),
        theme: theme(),
      );
      c.setPreset(PolarizationPreset.elliptical);
      c.setShowComponents(true);
      await _settle(tester);
      await tester.scrollUntilVisible(
        find.text('Adjust: amplitudes and phase difference'),
        200,
      );
      await tester.tap(find.text('Adjust: amplitudes and phase difference'));
      await _settle(tester);
      for (final PolarizationPreset p in PolarizationPreset.named) {
        c.setPreset(p);
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: p.label);
      }
      c.setPlaying(false);
      await _settle(tester);
    });
  }

  testWidgets('Antenna Pattern\'s polarization card opens this tile', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1280, 3000));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        routes: <String, WidgetBuilder>{
          AppRouter.polarization: (_) => const PolarizationScreen(),
        },
        home: const AntennaPatternScreen(),
      ),
    );
    await tester.pumpAndSettle();
    final Finder link = find.text('See it in 3D: open Polarization');
    await tester.scrollUntilVisible(link, 300);
    await tester.tap(link);
    await _settle(tester);
    expect(find.byType(PolarizationScreen), findsOneWidget);
    tester
        .widget<PolarizationStage>(find.byType(PolarizationStage))
        .controller
        .setPlaying(false);
    await _settle(tester);
  });
}
