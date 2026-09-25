// Widget tests for the Wi-Fi Lab "PHY Preamble Reference" screen.
//
// The numbers are pinned in test/services/wifi_lab/phy_preamble_test.dart;
// these cover the screen contract: catalog and route registration, the stage
// and controls as separate widgets over one model, opening a bit table with
// its evidence tags (unsettled ones labeled in words), the decision walk and
// the mystery mode, the LENGTH calculator's states, the bar's hit test and
// label packing, the copy text, and phone and desktop widths in both themes
// for Legacy, VHT and HE SU with a bit table open, with no sideways scroll.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_bit_table.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_painter.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/phy_preamble.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 390,
  double height = 844,
  PreambleSettings initial = const PreambleSettings(),
  PreambleMode mode = PreambleMode.explore,
  String? open,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: PhyPreambleScreen(
        key: UniqueKey(),
        initial: initial,
        initialMode: mode,
        initialSelection: open,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PhyPreambleModel _model(WidgetTester tester) =>
    tester.widget<PhyPreambleStage>(find.byType(PhyPreambleStage)).model;

/// [text] inside the open bit table only (the LENGTH card has tags too).
Finder _inTable(String text) =>
    find.descendant(of: find.byType(BitTableView), matching: find.text(text));

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  test('catalog and route register phy-preamble in Wi-Fi Lab', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final ToolEntry e = rf.tools.firstWhere(
      (ToolEntry t) => t.id == kPhyPreambleToolId,
    );
    expect(e.title, 'PHY Preamble Reference');
    expect(e.subgroup, 'Wi-Fi Lab');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/phy-preamble');
    expect(AppRouter.routes.containsKey('/tools/phy-preamble'), isTrue);
  });

  testWidgets('stage and controls are separate widgets over one model', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.byType(PhyPreambleStage), findsOneWidget);
    expect(find.byType(PhyPreambleControls), findsOneWidget);
    final PhyPreambleControls controls = tester.widget<PhyPreambleControls>(
      find.byType(PhyPreambleControls),
    );
    expect(identical(controls.model, _model(tester)), isTrue);
    expect(
      find.descendant(
        of: find.byType(PhyPreambleStage),
        matching: find.byType(PhyPreambleControls),
      ),
      findsNothing,
    );
  });

  testWidgets('fresh: nothing open; the list opens HE-SIG-A with its tags', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.textContaining('Nothing open.'), findsOneWidget);
    await _tap(tester, find.text('HE-SIG-A 8'));
    expect(_model(tester).selectedBlock!.name, 'HE-SIG-A');
    expect(find.text('HE-SIG-A (HE SU) · 52 bits'), findsOneWidget);
    expect(find.text('HE-SIG-A1 · 26 bits · BPSK'), findsOneWidget);
    expect(find.text('B8-B13'), findsOneWidget);
    // CRC and Tail are inferred, and say so in words.
    expect(find.text('INF · inferred'), findsWidgets);
    expect(find.text('S2'), findsWidgets);
    // Close.
    await _tap(tester, find.text('Close'));
    expect(_model(tester).selected, isNull);
  });

  testWidgets('single-source fields are labeled, never shown as settled', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const PreambleSettings(type: PpduType.heTb),
      open: 'HE-SIG-A',
    );
    expect(find.text('HE-SIG-A (HE TB) · 52 bits'), findsOneWidget);
    expect(find.text('P, single vendor · one source'), findsWidgets);
    expect(_inTable('S2'), findsNothing);

    await _pump(
      tester,
      initial: const PreambleSettings(type: PpduType.vht, widthMhz: 40),
      open: 'VHT-SIG-B',
    );
    expect(
      find.text('VHT-SIG-B, 40 MHz · layouts shown one by one'),
      findsOneWidget,
    );
    expect(find.text('S1 · one source'), findsWidgets);
    expect(_inTable('S2'), findsOneWidget); // the SERVICE CRC note only
  });

  testWidgets('the Data stub opens the SERVICE field', (
    WidgetTester tester,
  ) async {
    await _pump(tester, initial: const PreambleSettings(type: PpduType.vht));
    await _tap(tester, find.text('Data'));
    expect(find.text('SERVICE (VHT) · 16 bits'), findsOneWidget);
    expect(find.text('continues; not drawn to scale'), findsOneWidget);
  });

  testWidgets('Which PHY? walks the tree to a verdict', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const PreambleSettings(type: PpduType.heErSu),
      mode: PreambleMode.identify,
    );
    expect(find.textContaining('No question asked yet'), findsOneWidget);
    for (int i = 0; i < 4; i++) {
      await _tap(tester, find.text('Next step'));
    }
    expect(find.text('Verdict: HE ER SU'), findsOneWidget);
    expect(find.text('Walk complete'), findsOneWidget);
    await _tap(tester, find.text('Back'));
    expect(find.text('Verdict: HE ER SU'), findsNothing);
  });

  testWidgets('Mystery hides the name and the telling controls until the end', (
    WidgetTester tester,
  ) async {
    await _pump(tester, mode: PreambleMode.identify);
    await _tap(tester, find.text('Mystery'));
    final PhyPreambleModel m = _model(tester);
    expect(m.hidden, isTrue);
    expect(m.type, isNot(PpduType.heSu));
    expect(find.text('Mystery PPDU, drawn to scale'), findsOneWidget);
    expect(find.text('PPDU type'), findsNothing);
    expect(find.textContaining('Settings are hidden'), findsOneWidget);
    expect(find.textContaining(m.type.label), findsNothing);
    await _tap(tester, find.text('Reveal'));
    expect(m.hidden, isFalse);
    expect(find.text('${m.type.label}, drawn to scale'), findsOneWidget);
    expect(
      find.text('Verdict: ${DetectedFormat.expectedFor(m.type).label}'),
      findsOneWidget,
    );
  });

  testWidgets('LENGTH calculator: result, error, and non-HT disabled', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('ceil((200 - 20) / 4) x 3 - 3 - 2 = 130'), findsOneWidget);
    expect(find.text('20 + 4 x 45 = 200 µs'), findsOneWidget);

    final Finder field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.enterText(field, '10');
    await tester.pumpAndSettle();
    expect(find.textContaining('Cannot signal this.'), findsOneWidget);
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(find.text('Enter the PPDU duration in µs.'), findsOneWidget);
    await tester.enterText(field, '9000');
    await tester.pumpAndSettle();
    expect(find.textContaining('over the 12-bit maximum'), findsOneWidget);

    _model(tester).type = PpduType.nonHt;
    await tester.pumpAndSettle();
    expect(find.textContaining('nothing is spoofed'), findsOneWidget);
    expect(tester.widget<TextField>(field).enabled, isFalse);
  });

  test(
    'bar layout: hit test finds every block, lane labels never collide',
    timeout: const Timeout(Duration(seconds: 30)),
    () {
      const TextStyle style = TextStyle(fontSize: 13);
      for (final PpduType t in PpduType.values) {
        for (final double w in <double>[300, 600]) {
          final PreambleSettings s = PreambleSettings(
            type: t,
            streams: 8,
            sigSymbols: 3,
          );
          final PreambleBarLayout l = PreambleBarLayout.compute(
            blocks: preambleBlocks(s),
            width: w,
            labelStyle: style,
            textScaler: TextScaler.noScaling,
          );
          for (int i = 0; i < l.rects.length; i++) {
            expect(l.hitTest(l.rects[i].center), i, reason: '${t.label} $i');
          }
          final List<PreambleLabelPlacement> lane = l.labels
              .where((PreambleLabelPlacement p) => !p.inside)
              .toList();
          for (final PreambleLabelPlacement p in l.labels) {
            expect(p.rect.left, greaterThanOrEqualTo(-0.01));
            expect(p.rect.right, lessThanOrEqualTo(w + 0.01));
          }
          for (int a = 0; a < lane.length; a++) {
            for (int b = a + 1; b < lane.length; b++) {
              expect(
                lane[a].rect.overlaps(lane[b].rect),
                isFalse,
                reason: '${t.label} $w: ${lane[a].text} / ${lane[b].text}',
              );
            }
          }
          // Each leader lands on its own block and crosses no lower label.
          for (final PreambleLabelPlacement a in lane) {
            final Rect own = l.rects[a.block];
            expect(a.leaderX!, inInclusiveRange(own.left, own.right));
            for (final PreambleLabelPlacement b in lane) {
              if (b.rect.top <= a.rect.top) continue;
              expect(
                a.leaderX! < b.rect.left || a.leaderX! > b.rect.right,
                isTrue,
                reason: '${t.label} $w: ${a.text} leader crosses ${b.text}',
              );
            }
          }
          // The legacy 20 us stays to scale.
          expect(
            l.rects[2].right,
            closeTo(l.xFor(kLegacyPreambleTenths), 0.01),
          );
        }
      }
    },
  );

  test('copy text lists every field and the LENGTH', () {
    final PhyPreambleModel m = PhyPreambleModel(
      initial: const PreambleSettings(type: PpduType.vht, streams: 3),
    );
    addTearDown(m.dispose);
    final String text = m.copyText();
    expect(text, contains('VHT (802.11ac)'));
    expect(text, contains('VHT-SIG-A: 8 µs (BPSK, QBPSK)'));
    expect(text, contains('VHT-LTF: 16 µs'));
    expect(text, contains('Preamble: 52 µs (legacy 20 + 32 added)'));
    expect(text, contains('L-SIG LENGTH for a 200 µs PPDU: 132'));
    expect(text, isNot(contains('—')));
  });

  for (final String themeName in <String>['dark', 'light']) {
    for (final double w in <double>[390, 1280]) {
      for (final (PreambleSettings, String) c in <(PreambleSettings, String)>[
        (const PreambleSettings(type: PpduType.nonHt), 'L-SIG'),
        (const PreambleSettings(type: PpduType.vht, streams: 4), 'VHT-SIG-A'),
        (const PreambleSettings(type: PpduType.heSu, streams: 2), 'HE-SIG-A'),
      ]) {
        testWidgets(
          '${c.$1.type.shortLabel} with ${c.$2} open at $w px, $themeName, '
          'no sideways scroll',
          (WidgetTester tester) async {
            await _pump(
              tester,
              width: w,
              theme: themeName == 'dark' ? AppTheme.dark() : AppTheme.light(),
              initial: c.$1,
              open: c.$2,
            );
            expect(tester.takeException(), isNull);
            expect(_model(tester).selectedBlock!.name, c.$2);
            // Page-level scrollables only: a single-line TextField keeps its
            // own horizontal viewport for long input, which is not page
            // scroll.
            final Finder pageScrollables = find.byWidgetPredicate(
              (Widget w) => w is Scrollable,
            );
            for (final Element e in pageScrollables.evaluate()) {
              bool inField = false;
              e.visitAncestorElements((Element a) {
                if (a.widget is EditableText) inField = true;
                return !inField;
              });
              if (inField) continue;
              expect(
                (e.widget as Scrollable).axisDirection,
                AxisDirection.down,
              );
            }
            expect(find.textContaining('NaN'), findsNothing);
          },
        );
      }
    }
  }
}
