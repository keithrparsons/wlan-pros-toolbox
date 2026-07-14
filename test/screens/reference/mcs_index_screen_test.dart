// Tests for the MCS Index reference screen — structure, lookups, and rendering.
//
// The RATE VALUES are not pinned here. They live in
// test/screens/reference/mcs_index_source_table_test.dart, which transcribes
// mcsindex.net cell-by-cell and is the single oracle for what a rate should be.
// This file covers the screen's shape and behavior around that data.
//
// HISTORY WORTH KEEPING. This file used to pin values it had generated FROM THE
// CODE, and every one of them was wrong in a way that stayed green:
//   - `closeTo(1733.4, 0.1)` for VHT MCS 9 @ 160 MHz at 2 SS. The source says
//     1733.3. The tolerance was wide enough to hide a real defect.
//   - `closeTo(1201.0 * 4, 1e-9)` for HE MCS 11 at 4 SS. The source says 4803.9,
//     not 4804.0 — the app multiplied a rounded base instead of rounding the
//     product.
//   - a test asserting every exclusion sits at `<= 3` SS, which ACTIVELY FORBADE
//     the real 4 SS exclusion the source publishes.
// An expectation derived from the implementation tests nothing. It only freezes
// the bug. Rates come from the source.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/throughput_calc_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/mcs_index_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

void main() {
  /// Open the standard selector and choose [label].
  Future<void> pickStd(WidgetTester tester, String label) async {
    await tester.tap(find.byType(AppSelect<McsStd>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Open the spatial-streams selector and choose [label].
  Future<void> pickSs(WidgetTester tester, String label) async {
    await tester.tap(find.byType(AppSelect<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  group('table structure', () {
    test('802.11n columns and MCS 7 row metadata', () {
      const McsStdData ht = McsIndexScreen.ht;
      expect(ht.columns, ['20 LGI', '20 SGI', '40 LGI', '40 SGI']);
      final McsRow row = ht.rows[7];
      expect(row.mcs, 7);
      expect(row.modulation, '64-QAM');
      expect(row.codeRate, '5/6');
    });

    test('dataFor returns the right table per standard', () {
      expect(McsIndexScreen.dataFor(McsStd.n).rows.length, 8);
      expect(McsIndexScreen.dataFor(McsStd.ac).rows.length, 10);
      expect(McsIndexScreen.dataFor(McsStd.ax).rows.length, 12);
      expect(McsIndexScreen.dataFor(McsStd.be).rows.length, 14);
    });

    test('every row carries one rate per column', () {
      for (final McsStd std in McsStd.values) {
        final McsStdData data = McsIndexScreen.dataFor(std);
        for (final McsRow row in data.rows) {
          expect(
            row.exactRatesPerSs.length,
            data.columns.length,
            reason: '$std MCS ${row.mcs} has ${row.exactRatesPerSs.length} '
                'rates for ${data.columns.length} columns.',
          );
        }
      }
    });

    test('base rates are stored UNROUNDED', () {
      // The source publishes round(exact * streams, 1). Rounding the base first
      // and then multiplying drifts by up to 0.2 Mbps. If someone "tidies" these
      // constants to one decimal, ~110 cells silently go wrong again — so pin
      // the fact that at least one of them is not a 1-dp number.
      final double? base = McsIndexScreen.vht.rows[9].exactRatesPerSs[0];
      expect(base, isNotNull);
      expect(
        base,
        isNot(closeTo(96.3, 1e-9)),
        reason: 'VHT MCS 9 @ 20 MHz must keep its exact value '
            '(96.296...), not the display-rounded 96.3.',
      );
      expect(base, closeTo(96.2962962, 1e-6));
    });
  });

  group('802.11be (Wi-Fi 7 / EHT)', () {
    test('EHT exposes the 320 MHz column', () {
      expect(McsIndexScreen.eht.columns,
          ['20 MHz', '40 MHz', '80 MHz', '160 MHz', '320 MHz']);
    });

    test('EHT adds 4096-QAM MCS 12 and 13', () {
      const McsStdData eht = McsIndexScreen.eht;
      expect(eht.rows.length, 14);
      expect(eht.rows[12].mcs, 12);
      expect(eht.rows[12].modulation, '4096-QAM');
      expect(eht.rows[12].codeRate, '3/4');
      expect(eht.rows[13].mcs, 13);
      expect(eht.rows[13].modulation, '4096-QAM');
      expect(eht.rows[13].codeRate, '5/6');
    });
  });

  group('spatial-stream ceilings', () {
    test('the SS options offered match what each standard DEFINES', () {
      // 802.11n has no 5-8 stream mode: MCS 0-31 is 8 indices x 4 streams. The
      // screen used to offer 8 SS of 802.11n and return a rate for it.
      expect(McsIndexScreen.maxStreamsPerStd[McsStd.n], 4);
      expect(McsIndexScreen.maxStreamsPerStd[McsStd.ac], 8);
      expect(McsIndexScreen.maxStreamsPerStd[McsStd.ax], 8);
      expect(McsIndexScreen.maxStreamsPerStd[McsStd.be], 8);
    });

    test('one app, one number — the throughput calc agrees stream-for-stream',
        () {
      // App self-consistency: two screens must not disagree about how many
      // streams a standard has.
      const Map<McsStd, WifiStd> equivalent = <McsStd, WifiStd>{
        McsStd.n: WifiStd.ht,
        McsStd.ac: WifiStd.vht,
        McsStd.ax: WifiStd.he,
        McsStd.be: WifiStd.eht,
      };
      for (final MapEntry<McsStd, WifiStd> e in equivalent.entries) {
        expect(
          McsIndexScreen.maxStreamsPerStd[e.key],
          ThroughputCalcScreen.maxStreams[e.value],
          reason: 'MCS Index and Throughput Calc disagree on max streams for '
              '${e.key}.',
        );
      }
    });

    test('ss < 1 yields null', () {
      expect(
        McsIndexScreen.rate(
            std: McsStd.n, mcs: 0, columnIndex: 0, spatialStreams: 0),
        isNull,
      );
    });
  });

  group('out-of-range lookups', () {
    test('unknown MCS index yields null', () {
      expect(
        McsIndexScreen.rate(
            std: McsStd.n, mcs: 99, columnIndex: 0, spatialStreams: 1),
        isNull,
      );
    });

    test('out-of-range column yields null', () {
      expect(
        McsIndexScreen.rate(
            std: McsStd.n, mcs: 0, columnIndex: 9, spatialStreams: 1),
        isNull,
      );
    });
  });

  testWidgets('MCS Index screen renders in a 375x900 phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const McsIndexScreen()),
    );
    await tester.pump();

    expect(find.text('802.11 standard'), findsOneWidget);
    expect(find.text('Spatial streams'), findsOneWidget);
    // Default standard (802.11n) header + a known base cell.
    expect(find.text('20 LGI'), findsOneWidget);
    expect(find.text('6.5'), findsOneWidget);
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final double width in <double>[320, 375, 768, 1280]) {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const McsIndexScreen()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    }
  });

  testWidgets('above 4 SS the screen shows the honest notice, not a wall of N/A',
      (tester) async {
    // The unsourced state must be visibly DIFFERENT from an exclusion. A grid of
    // "N/A" would tell the user 8-stream 802.11be is invalid. It is not — we
    // just have no published rate for it.
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const McsIndexScreen()),
    );
    await tester.pump();

    // 802.11ac, so 5-8 SS are offered at all.
    await pickStd(tester, '802.11ac: Wi-Fi 5 (VHT)');

    // 4 SS: the table renders.
    await pickSs(tester, '4 SS');
    expect(find.byType(DataTable), findsOneWidget);

    // 5 SS: the table is replaced by the notice.
    await pickSs(tester, '5 SS');

    expect(find.byType(DataTable), findsNothing,
        reason: 'No table above the sourced ceiling — no invented rates.');
    expect(
      find.textContaining('No sourced rates above 4 spatial streams'),
      findsOneWidget,
    );
    expect(find.text('N/A'), findsNothing,
        reason: '"Unsourced" must never be rendered as "N/A". N/A is a claim '
            'the standard makes; this is a claim about our data.');
  });

  testWidgets('switching to 802.11n clamps a stale 8 SS selection to 4',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const McsIndexScreen()),
    );
    await tester.pump();

    // Go to 802.11ac and pick a stream count above 802.11n's ceiling of 4.
    // 5 SS, not 8: the dropdown overlay is virtualized and only builds the
    // first few items, so 6-8 are not tappable in a widget test. 5 is above 4,
    // which is all this test needs — the clamp logic is a single comparison.
    await pickStd(tester, '802.11ac: Wi-Fi 5 (VHT)');
    await pickSs(tester, '5 SS');

    // Back to 802.11n, which defines only 4 streams.
    await pickStd(tester, '802.11n: Wi-Fi 4 (HT)');

    // The stale 8 SS is clamped to 4 — 802.11n has no 8-stream mode — so the
    // table is back (4 SS is sourced) rather than the unsourced notice.
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.textContaining('×4 SS'), findsOneWidget);
  });
}
