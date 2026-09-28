// Widget tests for the Wi-Fi Classroom "Wi-Fi Through a Wall" screen.
//
// The physics is pinned in test/services/wifi_lab/wall_slab_physics_test.dart;
// these cover the screen contract: catalog registration beside an untouched
// rf-attenuation tool, reduced motion opens frozen on the stud wall and a
// normal open animates with a working Pause, the Wall list and its layers,
// the thickness error state keeps the last valid wall, the measured card's
// empty state and "Set the wall" action, metal renders without NaN, and
// phone and desktop widths in both themes lay out without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_multilayer_physics.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

/// One material, 102 mm of concrete: the base tool's opening wall.
const WallConfig _concrete = WallConfig(preset: WallPreset.custom);

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 390,
  double height = 844,
  bool reduceMotion = true,
  WallConfig initial = const WallConfig(),
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: reduceMotion,
        ),
        child: WifiThroughAWallScreen(initial: initial),
      ),
    ),
  );
  if (reduceMotion) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _valueOf(WidgetTester tester, String label) {
  final Finder row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  final List<Text> texts = tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .toList();
  return texts.last.data ?? '';
}

void main() {
  test('catalog registers wifi-through-a-wall in Wi-Fi Classroom', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final int i = rf.tools.indexWhere(
      (ToolEntry t) => t.id == kWifiThroughAWallToolId,
    );
    expect(i, greaterThan(0));
    final ToolEntry e = rf.tools[i];
    expect(e.title, 'Wi-Fi Through a Wall');
    expect(e.subgroup, 'RF and Propagation');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/wifi-through-a-wall');
    // The existing attenuation tool is a separate, untouched entry.
    expect(
      kToolCategories.any(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'rf-attenuation'),
      ),
      isTrue,
    );
  });

  testWidgets('reduced motion: opens frozen with Play offered', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('Wi-Fi Through a Wall'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.textContaining('Reduced motion is on'), findsOneWidget);
    // Default: the interior stud wall on channel 100 (5500 MHz), its loss
    // the multilayer result for its layers.
    expect(_valueOf(tester, 'Frequency'), '5500 MHz (ch 100)');
    expect(
      _valueOf(tester, 'Transmission loss'),
      fmtLossDb(
        MultilayerWall.compute(
          layers: WallPreset.studWall.layers,
          fGhz: 5.5,
        ).transmissionLossDb,
      ),
    );
    // A real wall has fixed layers: no material or thickness controls.
    expect(find.byType(TextField), findsNothing);
    expect(
      _valueOf(tester, 'Layers'),
      'Plasterboard 1.27 cm, Air 8.9 cm, Plasterboard 1.27 cm',
    );
  });

  testWidgets('the Wall list: every real wall, then one material', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Finder select = find.byWidgetPredicate(
      (Widget w) => w is AppSelect<WallPreset>,
    );
    expect(select, findsOneWidget);
    final AppSelect<WallPreset> s = tester.widget<AppSelect<WallPreset>>(
      select,
    );
    expect(
      <String>[for (final AppSelectItem<WallPreset> i in s.items) i.$2],
      <String>[
        'Interior stud wall',
        'Concrete elevator-shaft wall',
        'Solid wood door',
        'Double-pane window',
        'Single-pane window',
        'Brick wall, one brick thick',
        'One material, any thickness',
      ],
    );

    s.onChanged(WallPreset.elevatorShaft);
    await tester.pumpAndSettle();
    expect(_valueOf(tester, 'Layers'), 'Concrete 20.3 cm');
    expect(find.textContaining('reinforcing bars'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    tester.widget<AppSelect<WallPreset>>(select).onChanged(WallPreset.custom);
    await tester.pumpAndSettle();
    // One material: the material and thickness controls return, as they were.
    expect(find.byType(TextField), findsOneWidget);
    expect(_valueOf(tester, 'Transmission loss'), '14.3 dB');
    expect(find.text('Layers'), findsNothing);
  });

  testWidgets('copy text names the wall and its layers', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final WallSlabController c = tester
        .widget<WallSlabStage>(find.byType(WallSlabStage))
        .controller;
    expect(c.copyText(), contains('Interior stud wall, 11.4 cm'));
    expect(
      c.copyText(),
      contains(
        'Layers, front to back: Plasterboard 1.27 cm, Air 8.9 cm, '
        'Plasterboard 1.27 cm',
      ),
    );
  });

  testWidgets('on a real wall, "Set the wall" switches to one material', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(
      find.textContaining('Published measurements of plasterboard'),
      findsOneWidget,
    );
    final Finder use = find.text('Set the wall to 1.3 cm');
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    final WallSlabController c = tester
        .widget<WallSlabStage>(find.byType(WallSlabStage))
        .controller;
    expect(c.config.preset, WallPreset.custom);
    expect(c.config.material, WallMaterial.plasterboard);
    expect(c.config.thicknessMm, 13);
    expect(find.text('Set the wall to 1.3 cm'), findsNothing);
  });

  testWidgets('normal motion: animates on open, Pause stops it', (
    WidgetTester tester,
  ) async {
    await _pump(tester, reduceMotion: false);
    expect(find.text('Pause'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Play'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('thickness error keeps the last valid wall', (
    WidgetTester tester,
  ) async {
    await _pump(tester, initial: _concrete);
    final Finder field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.enterText(field, '0');
    await tester.pump();
    expect(find.text('Enter a thickness from 1 to 100 cm'), findsOneWidget);
    expect(_valueOf(tester, 'Transmission loss'), '14.3 dB');

    await tester.enterText(field, '1,27');
    await tester.pump();
    expect(find.text('Enter a thickness from 1 to 100 cm'), findsNothing);
    expect(find.textContaining('1.27 cm'), findsWidgets);
  });

  testWidgets('measured card: action sets the specimen thickness', (
    WidgetTester tester,
  ) async {
    await _pump(tester, initial: _concrete);
    final Finder use = find.text('Set the wall to 20.3 cm');
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(find.text('Set the wall to 20.3 cm'), findsNothing);
    expect(find.text('Set the wall to 10.2 cm'), findsOneWidget);
    expect(find.textContaining('Disagrees: measured is'), findsWidgets);
  });

  testWidgets('measured card empty state for a material with no data', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const WallConfig(
        preset: WallPreset.custom,
        material: WallMaterial.marble,
      ),
    );
    expect(
      find.textContaining('found no published measurement for marble'),
      findsOneWidget,
    );
  });

  testWidgets('thin plasterboard tells the resonance story', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const WallConfig(
        preset: WallPreset.custom,
        material: WallMaterial.plasterboard,
        thicknessMm: 12.7,
      ),
    );
    expect(find.textContaining('LESS than 2.4 GHz'), findsOneWidget);
  });

  testWidgets('Tx power: 0 to 30 dBm, default 20, drives the drawing, the '
      'level behind and the copy text, never the loss', (
    WidgetTester tester,
  ) async {
    await _pump(tester, initial: _concrete);
    final Finder tx = find.byWidgetPredicate(
      (Widget w) => w is Slider && w.max == kWallTxMaxDbm,
    );
    expect(tx, findsOneWidget);
    final Slider s = tester.widget<Slider>(tx);
    expect(s.min, 0);
    expect(s.max, 30);
    expect(s.value, 20);
    expect(find.text('20 dBm'), findsOneWidget);
    // 102 mm concrete at 5.5 GHz: 14.3 dB, so 5.7 dBm behind.
    expect(_valueOf(tester, 'Level behind the wall'), startsWith('5.7 dBm'));

    await tester.ensureVisible(tx);
    s.onChanged!(29.6);
    await tester.pumpAndSettle();
    expect(find.text('30 dBm'), findsOneWidget);
    expect(_valueOf(tester, 'Transmission loss'), '14.3 dB');
    expect(_valueOf(tester, 'Level behind the wall'), startsWith('15.7 dBm'));
    final WallSlabController c = tester
        .widget<WallSlabStage>(find.byType(WallSlabStage))
        .controller;
    expect(c.config.txPowerDbm, 30);
    final Finder painter = find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is WallWavePainter,
    );
    expect(
      (tester.widget<CustomPaint>(painter).painter! as WallWavePainter)
          .txPowerDbm,
      30,
    );
    expect(c.copyText(), contains('Tx power: 30.0 dBm'));
    expect(c.copyText(), contains('Behind the wall: 15.7 dBm'));
    expect(
      find.textContaining('Height shows the signal in dBm'),
      findsOneWidget,
    );
  });

  testWidgets('below the noise floor: flat behind, and a note says so', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const WallConfig(
        band: WifiBand.band6,
        channel: 117,
        preset: WallPreset.custom,
        thicknessMm: 1000,
        txPowerDbm: 0,
      ),
    );
    expect(
      find.textContaining('the signal is below the -95.0 dBm noise floor'),
      findsOneWidget,
    );
  });

  testWidgets('2 ft concrete at 5.5 GHz, Tx 20: above the floor, no note', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const WallConfig(preset: WallPreset.custom, thicknessMm: 610),
    );
    expect(find.textContaining('the signal is below'), findsNothing);
    expect(_valueOf(tester, 'Level behind the wall'), startsWith('-57.8 dBm'));
  });

  testWidgets('metal renders capped numbers, no NaN', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const WallConfig(
        preset: WallPreset.custom,
        material: WallMaterial.metal,
        thicknessMm: 47,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(_valueOf(tester, 'Transmission loss'), 'more than 150 dB');
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
  });

  for (final String themeName in <String>['dark', 'light']) {
    for (final double w in <double>[390, 1280]) {
      for (final WallPreset p in WallPreset.values) {
        if (p.isCustom) continue;
        testWidgets('lays out at $w px, $themeName, ${p.label}', (
          WidgetTester tester,
        ) async {
          await _pump(
            tester,
            width: w,
            theme: themeName == 'dark' ? AppTheme.dark() : AppTheme.light(),
            initial: WallConfig(preset: p),
          );
          expect(tester.takeException(), isNull);
          expect(find.textContaining('NaN'), findsNothing);
        });
      }
      for (final WallMaterial m in <WallMaterial>[
        WallMaterial.concrete,
        WallMaterial.glass,
        WallMaterial.plywood,
      ]) {
        testWidgets('lays out at $w px, $themeName, ${m.label}', (
          WidgetTester tester,
        ) async {
          await _pump(
            tester,
            width: w,
            theme: themeName == 'dark' ? AppTheme.dark() : AppTheme.light(),
            initial: WallConfig(
              preset: WallPreset.custom,
              material: m,
              thicknessMm: 1000,
            ),
          );
          expect(tester.takeException(), isNull);
          // No sideways scroll on the screen. A text field scrolls its own
          // line horizontally; that is the field, not the page.
          final Finder inFields = find.descendant(
            of: find.byType(EditableText),
            matching: find.byType(Scrollable),
          );
          final Set<Scrollable> fieldScrollers = tester
              .widgetList<Scrollable>(inFields)
              .toSet();
          for (final Scrollable s in tester.widgetList<Scrollable>(
            find.byType(Scrollable),
          )) {
            if (fieldScrollers.contains(s)) continue;
            expect(s.axisDirection, AxisDirection.down);
          }
        });
      }
    }
  }
}
