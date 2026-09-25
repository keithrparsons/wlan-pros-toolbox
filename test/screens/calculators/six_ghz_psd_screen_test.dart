// Widget tests for the Wi-Fi Lab 6 GHz Power and PSD screen.
//
// The regulatory math is pinned in
// test/services/wifi_lab/six_ghz_psd_math_test.dart; these tests cover the
// screen contract: registration, the default readout, the empty state, the
// region switch, the SP client following its AP, width picking by tap and by
// slider, the spectrum view, the MCS table read from Signal Thresholds, the
// stage/controls split, and the layout at 390 x 844 and 1280 wide in both
// themes without overflow or sideways scrolling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_chart.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/six_ghz_psd_math.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.dark(), home: const SixGhzPsdScreen()),
  );
  await tester.pumpAndSettle();
}

/// No horizontally scrolling Scrollable anywhere on screen.
void _expectNoSidewaysScroll(WidgetTester tester) {
  final Iterable<Scrollable> sideways = tester
      .widgetList<Scrollable>(find.byType(Scrollable))
      .where(
        (Scrollable s) =>
            s.axisDirection == AxisDirection.left ||
            s.axisDirection == AxisDirection.right,
      );
  expect(sideways, isEmpty, reason: 'nothing may scroll sideways');
}

/// Every laid-out Text sits inside the viewport width.
void _expectTextInsideWidth(WidgetTester tester, double width) {
  for (final Element e in find.byType(Text).evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final Offset tl = ro.localToGlobal(Offset.zero);
    expect(
      tl.dx + ro.size.width,
      lessThanOrEqualTo(width + 0.5),
      reason: 'text "${(e.widget as Text).data}" runs past $width px',
    );
    expect(tl.dx, greaterThanOrEqualTo(-0.5));
  }
}

Finder _classRow(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell));

Future<void> _toggleClass(WidgetTester tester, String label) async {
  final Finder row = _classRow(label).first;
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

void main() {
  test('catalog registers six-ghz-psd in Wi-Fi Lab', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final int i = rf.tools.indexWhere(
      (ToolEntry t) => t.id == kSixGhzPsdToolId,
    );
    expect(i, isNonNegative);
    final ToolEntry e = rf.tools[i];
    expect(e.title, '6 GHz Power and PSD');
    expect(e.subgroup, 'Wi-Fi Lab');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/six-ghz-psd');
    expect(rf.tools[i - 1].subgroup, 'Wi-Fi Lab'); // shelf, not slot (2026-09-25 merge)
  });

  test('MCS steps are read from Signal Thresholds, MCS 0 at 5 dB', () {
    final List<PsdMcsStep> s = psdMcsSteps();
    expect(s, isNotEmpty);
    expect(s.first.minSnrDb, 5);
    expect(s.first.label, startsWith('MCS 0'));
    expect(s.last.label, startsWith('MCS 11'));
    final SixGhzPsdModel m = SixGhzPsdModel();
    addTearDown(m.dispose);
    expect(m.mcsFor(4.9), isNull);
    expect(m.mcsFor(24)!.label, startsWith('MCS 7'));
  });

  test('every class has a palette hue and a unique stroke-marker pair', () {
    for (final PsdRegion r in PsdRegion.values) {
      final List<PowerClass> cs = PowerClass.forRegion(r);
      expect(
        cs.map((PowerClass c) => kPsdClassLook[c]).toSet().length,
        cs.length,
        reason: 'no two $r classes may look the same without color',
      );
    }
    for (final PowerClass c in PowerClass.values) {
      expect(PsdPalette.of(c, AppColorScheme.dark()), isNotNull);
      expect(PsdPalette.of(c, AppColorScheme.light()), isNotNull);
    }
  });

  testWidgets('default readout at 80 MHz and 10 m matches the math', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('6 GHz Power and PSD'), findsOneWidget);
    expect(find.text('At 80 MHz, 10 m'), findsOneWidget);
    // SP AP 36, LPI AP 24, VLP 14 dBm at 80 MHz.
    expect(find.text('36.0 dBm'), findsOneWidget);
    expect(find.text('24.0 dBm'), findsOneWidget);
    expect(find.text('14.0 dBm'), findsOneWidget);
    // FSPL at 6105 MHz, 10 m = 68.16 dB; noise -87.97 dBm at 80 MHz, NF 7.
    expect(find.textContaining('Noise floor -88.0 dBm'), findsOneWidget);
    expect(find.textContaining('Free-space loss 68.2 dB'), findsOneWidget);
    // SNR: SP 55.8, LPI 43.8, VLP 33.8 dB.
    expect(find.text('55.8 dB'), findsOneWidget);
    expect(find.text('43.8 dB'), findsOneWidget);
    expect(find.text('33.8 dB'), findsOneWidget);
    expect(find.textContaining('PSD-limited at 80 MHz'), findsOneWidget);
    expect(find.textContaining('Cap-limited at 80 MHz'), findsNWidgets(2));
    expect(find.textContaining('9 channels of 80 MHz'), findsOneWidget);
    expect(find.textContaining('14 channels of 80 MHz'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('LPI SNR holds as the width changes; SP SNR falls 3 dB', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Slider width = tester.widget<Slider>(
      find.descendant(
        of: find.byType(SixGhzPsdStage),
        matching: find.byType(Slider),
      ),
    );
    width.onChanged!(3); // 160 MHz
    await tester.pumpAndSettle();
    expect(find.text('At 160 MHz, 10 m'), findsOneWidget);
    expect(find.text('27.0 dBm'), findsOneWidget);
    expect(find.text('43.8 dB'), findsOneWidget, reason: 'LPI holds');
    expect(find.text('52.8 dB'), findsOneWidget, reason: 'SP 55.8 - 3');
  });

  testWidgets('tapping a chart column picks that width', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Finder chart = find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is PsdWidthChartPainter,
    );
    final Rect r = tester.getRect(chart);
    final double plotW = r.width - PsdChartPad.left - PsdChartPad.right;
    // First column: 20 MHz.
    await tester.tapAt(
      Offset(r.left + PsdChartPad.left + plotW * 0.1, r.center.dy),
    );
    await tester.pumpAndSettle();
    expect(find.text('At 20 MHz, 10 m'), findsOneWidget);
    expect(find.text('18.0 dBm'), findsOneWidget);
    expect(find.text('8.0 dBm'), findsOneWidget);
    // Last column: 320 MHz.
    await tester.tapAt(
      Offset(r.left + PsdChartPad.left + plotW * 0.95, r.center.dy),
    );
    await tester.pumpAndSettle();
    expect(find.text('At 320 MHz, 10 m'), findsOneWidget);
    expect(find.text('30.0 dBm'), findsOneWidget);
  });

  testWidgets('SP client follows its AP authorized power, 6 dB lower', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    await _toggleClass(tester, 'Standard Power client');
    expect(find.text('30.0 dBm'), findsOneWidget);
    final Finder spSlider = find.byWidgetPredicate(
      (Widget w) =>
          w is Slider &&
          w.semanticFormatterCallback != null &&
          w.semanticFormatterCallback!(30).startsWith('Standard Power AP'),
    );
    tester.widget<Slider>(spSlider).onChanged!(30);
    await tester.pumpAndSettle();
    // SP AP now held to its 30 dBm grant; its client to 24.
    expect(find.text('30.0 dBm'), findsOneWidget);
    expect(find.text('24.0 dBm'), findsNWidgets(2)); // client + LPI AP
    expect(
      find.textContaining("6 dB below the AP's authorized 30 dBm"),
      findsOneWidget,
    );
    expect(find.textContaining('the AFC authorized 30.0 dBm'), findsOneWidget);
  });

  testWidgets('every class off shows the empty state and disables inputs', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    for (final String c in <String>[
      'Standard Power AP',
      'Low Power Indoor AP',
      'Very Low Power device',
    ]) {
      await _toggleClass(tester, c);
    }
    expect(find.textContaining('No class is on.'), findsOneWidget);
    final Slider width = tester.widget<Slider>(
      find.descendant(
        of: find.byType(SixGhzPsdStage),
        matching: find.byType(Slider),
      ),
    );
    expect(width.onChanged, isNull, reason: 'width disabled when empty');
    final Iterable<Slider> grants = tester
        .widgetList<Slider>(find.byType(Slider))
        .where(
          (Slider s) =>
              s.semanticFormatterCallback?.call(20).contains('authorized') ??
              false,
        );
    expect(grants, hasLength(2));
    expect(grants.every((Slider s) => s.onChanged == null), isTrue);
    await tester.tap(find.text('Spectrum'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('EU: LPI 23 and VLP 14 at every width, no client offset', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    await tester.tap(find.text('EU (ETSI)'));
    await tester.pumpAndSettle();
    expect(find.text('23.0 dBm'), findsOneWidget);
    expect(find.text('14.0 dBm'), findsOneWidget);
    expect(find.textContaining('The EU has no client offset'), findsWidgets);
    expect(find.text('Standard Power AP (AFC)'), findsNothing);
    expect(find.textContaining('6 channels of 80 MHz'), findsNWidgets(2));
    // Back to US keeps the US selection.
    await tester.tap(find.text('US (FCC)'));
    await tester.pumpAndSettle();
    expect(find.text('36.0 dBm'), findsOneWidget);
  });

  testWidgets('spectrum view draws one class as a PSD block', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Spectrum'));
    await tester.pumpAndSettle();
    final PsdSpectrumPainter p =
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (Widget w) =>
                        w is CustomPaint && w.painter is PsdSpectrumPainter,
                  ),
                )
                .painter!
            as PsdSpectrumPainter;
    // Default focus: LPI AP at 80 MHz, 5 dBm/MHz, a PSD-limited block.
    expect(p.selected!.widthMHz, 80);
    expect(p.selected!.psdDbmPerMHz, closeTo(5, 1e-9));
    expect(p.psdLimit, 5);
    expect(p.others, hasLength(4));
    expect(p.blockLabel, contains('= 24.0 dBm'));
    expect(find.textContaining('LPI AP: PSD (dBm/MHz)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stage and controls are separate widgets', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.byType(SixGhzPsdStage), findsOneWidget);
    expect(find.byType(SixGhzPsdControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SixGhzPsdStage),
        matching: find.byType(SixGhzPsdControls),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(SixGhzPsdControls),
        matching: find.byType(SixGhzPsdStage),
      ),
      findsNothing,
    );
  });

  test('copy payload lists every shown class, and is off when empty', () {
    final SixGhzPsdModel m = SixGhzPsdModel();
    addTearDown(m.dispose);
    final String t = m.copyText()!;
    expect(t, contains('LPI AP\t24.0\t-88.0\t43.8\t14\tPSD-limited'));
    expect(t, contains('SP AP: 36.0 / 36.0 / 36.0 / 36.0 / 36.0'));
    for (final PowerClass c in m.classes) {
      m.setShown(c, false);
    }
    expect(m.copyText(), isNull);
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1280, 900),
    ]) {
      testWidgets('$name theme at ${size.width.toInt()} wide renders cleanly', (
        WidgetTester tester,
      ) async {
        await _pump(tester, theme: theme(), size: size);
        // Widest content: every US class on.
        for (final String c in <String>[
          'Fixed client device',
          'Standard Power client',
          'Subordinate device',
          'Low Power Indoor client',
          'Geofenced Variable Power AP',
          'Geofenced Variable Power client',
        ]) {
          await _toggleClass(tester, c);
        }
        expect(tester.takeException(), isNull);
        _expectNoSidewaysScroll(tester);
        _expectTextInsideWidth(tester, size.width);
        for (final PsdView v in PsdView.values) {
          final Finder seg = find.text(v.label).first;
          await tester.ensureVisible(seg);
          await tester.tap(seg);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        _expectTextInsideWidth(tester, size.width);
      });
    }
  }
}
