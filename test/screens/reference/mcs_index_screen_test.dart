// Tests for the MCS Index reference table.
//
// The dataset is a verbatim port of the RF Tools PWA (app.js MCS_N / MCS_AC /
// MCS_AX, rendered by buildMCSTable). Every expected value below comes straight
// from those PWA consts, so the native app and the PWA agree cell-for-cell. The
// PWA scales each single-stream rate by the selected spatial-stream count
// (`r * ss`); these tests verify both the base (1 SS) cells and the scaling.
//
// One widget test confirms the screen pumps and renders in a phone-sized
// viewport (see test/widget_test.dart _withViewport) without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/mcs_index_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('MCS dataset — verbatim PWA values (1 SS)', () {
    test('802.11n MCS 7 rates match PWA MCS_N [65, 72.2, 135, 150]', () {
      const McsStdData ht = McsIndexScreen.ht;
      expect(ht.columns, ['20 LGI', '20 SGI', '40 LGI', '40 SGI']);
      final McsRow row = ht.rows[7];
      expect(row.mcs, 7);
      expect(row.modulation, '64-QAM');
      expect(row.codeRate, '5/6');
      expect(row.ratesPerSs, [65, 72.2, 135, 150]);
    });

    test('802.11n MCS 0 base cell — 20 LGI = 6.5 Mbps (PWA)', () {
      expect(
        McsIndexScreen.rate(
          std: McsStd.n,
          mcs: 0,
          columnIndex: 0,
          spatialStreams: 1,
        ),
        6.5,
      );
    });

    test('802.11ac MCS 9 @ 20 MHz is invalid (PWA null → N/A)', () {
      final McsRow row = McsIndexScreen.vht.rows[9];
      expect(row.mcs, 9);
      expect(row.ratesPerSs[0], isNull);
      expect(
        McsIndexScreen.rate(
          std: McsStd.ac,
          mcs: 9,
          columnIndex: 0,
          spatialStreams: 1,
        ),
        isNull,
      );
    });

    test('802.11ac MCS 9 @ 160 MHz = 866.7 Mbps (PWA)', () {
      expect(
        McsIndexScreen.rate(
          std: McsStd.ac,
          mcs: 9,
          columnIndex: 3,
          spatialStreams: 1,
        ),
        866.7,
      );
    });

    test('802.11ax MCS 11 @ 160 MHz = 1200.9 Mbps (PWA MCS_AX)', () {
      final McsRow row = McsIndexScreen.he.rows[11];
      expect(row.modulation, '1024-QAM');
      expect(row.codeRate, '5/6');
      expect(row.ratesPerSs, [143.4, 286.8, 600.4, 1200.9]);
      expect(
        McsIndexScreen.rate(
          std: McsStd.ax,
          mcs: 11,
          columnIndex: 3,
          spatialStreams: 1,
        ),
        1200.9,
      );
    });
  });

  group('Spatial-stream scaling (PWA r * ss)', () {
    test('802.11ax MCS 11 @ 160 MHz × 4 SS = 4803.6 Mbps', () {
      final double? r = McsIndexScreen.rate(
        std: McsStd.ax,
        mcs: 11,
        columnIndex: 3,
        spatialStreams: 4,
      );
      expect(r, closeTo(1200.9 * 4, 1e-9));
    });

    test('a null base cell stays null at any SS', () {
      expect(
        McsIndexScreen.rate(
          std: McsStd.ac,
          mcs: 9,
          columnIndex: 0,
          spatialStreams: 8,
        ),
        isNull,
      );
    });

    test('ss < 1 yields null', () {
      expect(
        McsIndexScreen.rate(
          std: McsStd.n,
          mcs: 0,
          columnIndex: 0,
          spatialStreams: 0,
        ),
        isNull,
      );
    });
  });

  group('Out-of-range lookups', () {
    test('unknown MCS index yields null', () {
      expect(
        McsIndexScreen.rate(
          std: McsStd.n,
          mcs: 99,
          columnIndex: 0,
          spatialStreams: 1,
        ),
        isNull,
      );
    });

    test('out-of-range column yields null', () {
      expect(
        McsIndexScreen.rate(
          std: McsStd.n,
          mcs: 0,
          columnIndex: 9,
          spatialStreams: 1,
        ),
        isNull,
      );
    });

    test('dataFor returns the right table per standard', () {
      expect(McsIndexScreen.dataFor(McsStd.n).rows.length, 8);
      expect(McsIndexScreen.dataFor(McsStd.ac).rows.length, 10);
      expect(McsIndexScreen.dataFor(McsStd.ax).rows.length, 12);
    });
  });

  testWidgets('MCS Index screen renders in a 375x900 phone viewport', (
    tester,
  ) async {
    // Phone-viewport smoke: pumps, renders the default 802.11n table, and shows
    // a known cell (MCS 0 / 20 LGI = 6.5) without a RenderFlex overflow.
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const McsIndexScreen(),
      ),
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
    // Multi-width overflow regression: the MCS table must not RenderFlex
    // overflow at small phone (320), phone (375), tablet (768), or desktop
    // (1280). Tall height so vertical scroll content never false-triggers.
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
}
