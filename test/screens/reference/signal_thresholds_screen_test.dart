// Tests for the Signal Thresholds reference screen.
//
// Dataset tests assert the load-bearing thresholds: the RSSI quality-scale
// bands use KEITH PARSONS' OWN canonical values (Excellent > -60, Good
// -60..-67, Fair -67..-72, Poor -73 or weaker — confirmed 2026-07-12,
// domain-proof over consensus, GL-005). The screen builds these from the single
// source WifiGradingBands.kRssiBands; the values below are hand-typed from
// Keith's confirmed bands (NOT read back from the constant under test), so a
// drift on either side breaks this — that is the point. The per-application
// RSSI/SNR targets and the SNR/MCS floor are ported from the rf-tools-pwa
// `rssi` tool.
//
// The widget-viewport smoke test lives in test/widget_test.dart (uses the
// shared private `_withViewport` phone-viewport helper there). A multi-width
// overflow regression below pumps the screen at 320/375/768/1280 widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/signal_thresholds_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Signal Thresholds dataset', () {
    AppThreshold byApp(String name) => SignalThresholdsScreen.kAppThresholds
        .firstWhere((AppThreshold t) => t.application == name);

    test('VoIP target is -67 dBm / 25 dB SNR', () {
      final AppThreshold voip = byApp('VoIP / Real-time');
      expect(voip.minRssi, '-67 dBm');
      expect(voip.minSnr, '25 dB');
    });

    test('HD video target is -70 dBm / 20 dB SNR', () {
      final AppThreshold video = byApp('Video streaming (HD)');
      expect(video.minRssi, '-70 dBm');
      expect(video.minSnr, '20 dB');
    });

    test('General browsing data target is -70 dBm / 15 dB SNR', () {
      final AppThreshold data = byApp('General browsing');
      expect(data.minRssi, '-70 dBm');
      expect(data.minSnr, '15 dB');
    });

    test('Location / RTLS target is -75 dBm / 15 dB SNR', () {
      final AppThreshold loc = byApp('Location / RTLS');
      expect(loc.minRssi, '-75 dBm');
      expect(loc.minSnr, '15 dB');
    });

    test('Email / basic connectivity target is -75 dBm / 10 dB SNR', () {
      final AppThreshold email = byApp('Email / basic data');
      expect(email.minRssi, '-75 dBm');
      expect(email.minSnr, '10 dB');
    });

    test('all six PWA application rows are present', () {
      expect(SignalThresholdsScreen.kAppThresholds.length, 6);
    });

    test("Keith's RSSI bands carry his confirmed canonical ranges", () {
      // Hand-typed from Keith's confirmed bands (2026-07-12), NOT derived from
      // WifiGradingBands — so this test would catch the screen drifting off the
      // canonical scale in either direction.
      String range(String label) => SignalThresholdsScreen.kSignalBands
          .firstWhere((SignalBand b) => b.label == label)
          .range;
      expect(range('Excellent'), '> -60 dBm');
      expect(range('Good'), '-60 to -67');
      expect(range('Fair'), '-67 to -72');
      expect(range('Poor'), '-73 or weaker');
    });

    test('four RSSI quality bands are present, no orphaned "Weak"', () {
      expect(SignalThresholdsScreen.kSignalBands.length, 4);
      expect(
        SignalThresholdsScreen.kSignalBands.map((SignalBand b) => b.label),
        <String>['Excellent', 'Good', 'Fair', 'Poor'],
      );
    });

    test('"Excellent" grades good, "Fair" marginal, "Poor" bad', () {
      SignalGrade grade(String label) => SignalThresholdsScreen.kSignalBands
          .firstWhere((SignalBand b) => b.label == label)
          .grade;
      expect(grade('Excellent'), SignalGrade.good);
      expect(grade('Fair'), SignalGrade.marginal);
      expect(grade('Poor'), SignalGrade.bad);
    });

    test('SNR/MCS table runs MCS 0 at 5 dB up to MCS 11 at 35 dB', () {
      final List<SnrMcsRow> rows = SignalThresholdsScreen.kSnrMcsRows;
      expect(rows.length, 12);
      expect(rows.first.minSnr, '5 dB');
      expect(rows.first.mcs, 'MCS 0 - BPSK 1/2');
      expect(rows.last.minSnr, '35 dB');
      expect(rows.last.mcs, 'MCS 11 - 1024-QAM 5/6');
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    // Multi-width overflow regression: the threshold tables must not RenderFlex
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
        MaterialApp(
          theme: AppTheme.dark(),
          home: const SignalThresholdsScreen(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    }
  });
}
