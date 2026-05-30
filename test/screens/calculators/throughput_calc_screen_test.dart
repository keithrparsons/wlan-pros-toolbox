// Tests for the Wi-Fi Throughput calculator.
//
// The math is verified against the RF Tools PWA reference (app.js
// calcThroughput, with the option tables from updateTputOptions):
//   phyRate  = (Nsd · MCS_BPS[mcs] · streams) / symbolTime
//   realRate = phyRate · efficiency(std)
// Expected values below were computed from those exact tables so the native app
// and PWA agree to the decimal.
//
// One widget test confirms the screen pumps and renders its selectors and
// result in a phone-width viewport.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/throughput_calc_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Throughput math (pure) — matches PWA app.js calcThroughput', () {
    test('PWA default: HE / 20 MHz / MCS 0 / 1 SS / 0.8 µs GI', () {
      // nsd[he][20]=234, bps[0]=0.5, ss=1, sym[he][0.8]=13.6.
      final double? phy = ThroughputCalcScreen.phyRateMbps(
        std: WifiStd.he,
        bandwidthMHz: 20,
        mcs: 0,
        streams: 1,
        giKey: '0.8',
      );
      final double? real = ThroughputCalcScreen.realRateMbps(
        std: WifiStd.he,
        bandwidthMHz: 20,
        mcs: 0,
        streams: 1,
        giKey: '0.8',
      );
      expect(phy, closeTo(8.602941176470589, 1e-9));
      expect(real, closeTo(6.538235294117648, 1e-9)); // ×0.76
    });

    test('EHT / 320 MHz / MCS 13 / 8 SS / 0.8 µs GI — top of the stack', () {
      final double? phy = ThroughputCalcScreen.phyRateMbps(
        std: WifiStd.eht,
        bandwidthMHz: 320,
        mcs: 13,
        streams: 8,
        giKey: '0.8',
      );
      final double? real = ThroughputCalcScreen.realRateMbps(
        std: WifiStd.eht,
        bandwidthMHz: 320,
        mcs: 13,
        streams: 8,
        giKey: '0.8',
      );
      expect(phy, closeTo(23058.823529411766, 1e-6));
      expect(real, closeTo(18447.058823529413, 1e-6)); // ×0.80
    });

    test('VHT / 80 MHz / MCS 9 / 2 SS / 0.4 µs (short) GI', () {
      final double? real = ThroughputCalcScreen.realRateMbps(
        std: WifiStd.vht,
        bandwidthMHz: 80,
        mcs: 9,
        streams: 2,
        giKey: '0.4',
      );
      expect(real, closeTo(624.00312, 1e-6)); // 866.671 × 0.72
    });

    test('HT / 40 MHz / MCS 7 / 4 SS / 0.4 µs GI', () {
      final double? phy = ThroughputCalcScreen.phyRateMbps(
        std: WifiStd.ht,
        bandwidthMHz: 40,
        mcs: 7,
        streams: 4,
        giKey: '0.4',
      );
      final double? real = ThroughputCalcScreen.realRateMbps(
        std: WifiStd.ht,
        bandwidthMHz: 40,
        mcs: 7,
        streams: 4,
        giKey: '0.4',
      );
      expect(phy, closeTo(600.0, 1e-9));
      expect(real, closeTo(420.0, 1e-9)); // ×0.70
    });

    test('HE / 160 MHz / MCS 11 / 4 SS / 3.2 µs GI', () {
      final double? real = ThroughputCalcScreen.realRateMbps(
        std: WifiStd.he,
        bandwidthMHz: 160,
        mcs: 11,
        streams: 4,
        giKey: '3.2',
      );
      expect(real, closeTo(3103.32092, 1e-5)); // 4083.317 × 0.76
    });
  });

  group('Invalid combinations blank the output (PWA showError paths)', () {
    test('bandwidth not valid for the standard → null', () {
      // 320 MHz exists only for EHT — invalid Nsd lookup for HE.
      expect(
        ThroughputCalcScreen.phyRateMbps(
          std: WifiStd.he,
          bandwidthMHz: 320,
          mcs: 0,
          streams: 1,
          giKey: '0.8',
        ),
        isNull,
      );
    });

    test('guard interval not valid for the standard → null', () {
      // 0.4 µs is an HT/VHT key, not an HE symbol-time key.
      expect(
        ThroughputCalcScreen.phyRateMbps(
          std: WifiStd.he,
          bandwidthMHz: 20,
          mcs: 0,
          streams: 1,
          giKey: '0.4',
        ),
        isNull,
      );
    });

    test('MCS above the standard maximum → null', () {
      // HT tops out at MCS 7.
      expect(
        ThroughputCalcScreen.phyRateMbps(
          std: WifiStd.ht,
          bandwidthMHz: 20,
          mcs: 8,
          streams: 1,
          giKey: '0.8',
        ),
        isNull,
      );
    });

    test('zero spatial streams → null', () {
      expect(
        ThroughputCalcScreen.phyRateMbps(
          std: WifiStd.he,
          bandwidthMHz: 20,
          mcs: 0,
          streams: 0,
          giKey: '0.8',
        ),
        isNull,
      );
    });
  });

  group('Constant tables match the PWA', () {
    test('per-standard max MCS', () {
      expect(ThroughputCalcScreen.maxMcs[WifiStd.ht], 7);
      expect(ThroughputCalcScreen.maxMcs[WifiStd.vht], 9);
      expect(ThroughputCalcScreen.maxMcs[WifiStd.he], 11);
      expect(ThroughputCalcScreen.maxMcs[WifiStd.eht], 13);
    });

    test('per-standard efficiency', () {
      expect(ThroughputCalcScreen.eff[WifiStd.ht], 0.70);
      expect(ThroughputCalcScreen.eff[WifiStd.vht], 0.72);
      expect(ThroughputCalcScreen.eff[WifiStd.he], 0.76);
      expect(ThroughputCalcScreen.eff[WifiStd.eht], 0.80);
    });

    test('MCS 0 is BPSK ½, MCS 13 is 4096-QAM ⅚', () {
      expect(ThroughputCalcScreen.mcsMod[0], 'BPSK ½');
      expect(ThroughputCalcScreen.mcsMod[13], '4096-QAM ⅚');
    });
  });

  group('ThroughputCalcScreen widget', () {
    testWidgets('renders title, selectors, and result in a phone viewport',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const ThroughputCalcScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Throughput'), findsWidgets);
        expect(find.text('Wi-Fi standard'), findsOneWidget);
        expect(find.text('Channel width'), findsOneWidget);
        expect(find.text('MCS index'), findsOneWidget);
        expect(find.text('Spatial streams'), findsOneWidget);
        expect(find.text('Guard interval'), findsOneWidget);
        expect(find.text('Est. real throughput'), findsOneWidget);

        // PWA default (HE / 20 / MCS 0 / 1 SS / 0.8 µs) → real 6.5 Mbps.
        expect(find.text('6.5'), findsOneWidget);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart `_withViewport`.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
