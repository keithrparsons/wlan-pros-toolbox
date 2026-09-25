// Widget tests for the Wi-Fi Lab "Wi-Fi Through a Wall" screen.
//
// The physics is pinned in test/services/wifi_lab/wall_slab_physics_test.dart;
// these cover the screen contract: catalog registration beside an untouched
// rf-attenuation tool, reduced motion opens frozen and a normal open animates
// with a working Pause, the thickness error state keeps the last valid wall,
// the measured card's empty state and "Set the wall" action, metal renders
// without NaN, and phone and desktop widths in both themes lay out without
// overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

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
  test('catalog registers wifi-through-a-wall in Wi-Fi Lab', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final int i = rf.tools.indexWhere(
      (ToolEntry t) => t.id == kWifiThroughAWallToolId,
    );
    expect(i, greaterThan(0));
    final ToolEntry e = rf.tools[i];
    expect(e.title, 'Wi-Fi Through a Wall');
    expect(e.subgroup, 'Wi-Fi Lab');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/wifi-through-a-wall');
    expect(rf.tools[i - 1].id, 'medium-access-simulator');
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
    // Default: 102 mm concrete on channel 100 (5500 MHz).
    expect(_valueOf(tester, 'Frequency'), '5500 MHz (ch 100)');
    expect(_valueOf(tester, 'Transmission loss'), '14.3 dB');
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
    await _pump(tester);
    final Finder field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.enterText(field, '0');
    await tester.pump();
    expect(find.text('Enter a thickness from 1 to 500 mm'), findsOneWidget);
    expect(_valueOf(tester, 'Transmission loss'), '14.3 dB');

    await tester.enterText(field, '12,7');
    await tester.pump();
    expect(find.text('Enter a thickness from 1 to 500 mm'), findsNothing);
    expect(find.textContaining('12.7 mm'), findsWidgets);
  });

  testWidgets('measured card: action sets the specimen thickness', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Finder use = find.text('Set the wall to 203 mm');
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(find.text('Set the wall to 203 mm'), findsNothing);
    expect(find.text('Set the wall to 102 mm'), findsOneWidget);
    expect(find.textContaining('Disagrees: measured is'), findsWidgets);
  });

  testWidgets('measured card empty state for a material with no data', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const WallConfig(material: WallMaterial.marble),
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
        material: WallMaterial.plasterboard,
        thicknessMm: 12.7,
      ),
    );
    expect(find.textContaining('LESS than 2.4 GHz'), findsOneWidget);
  });

  testWidgets('metal renders capped numbers, no NaN', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const WallConfig(material: WallMaterial.metal, thicknessMm: 47),
    );
    expect(tester.takeException(), isNull);
    expect(_valueOf(tester, 'Transmission loss'), 'more than 150 dB');
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
  });

  for (final String themeName in <String>['dark', 'light']) {
    for (final double w in <double>[390, 1280]) {
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
            initial: WallConfig(material: m, thicknessMm: 500),
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
