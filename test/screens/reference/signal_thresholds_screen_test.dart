// Tests for the Signal Thresholds reference screen.
//
// Dataset tests assert the load-bearing thresholds ported VERBATIM from the
// rf-tools-pwa `rssi` tool (data-tool="rssi"): the per-application RSSI/SNR
// targets, the RSSI quality-scale bands, and the SNR/MCS floor. If a value
// here drifts from the PWA, these break — that is the point.
//
// The widget-viewport smoke test lives in test/widget_test.dart (uses the
// shared private `_withViewport` phone-viewport helper there).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/signal_thresholds_screen.dart';

void main() {
  group('Signal Thresholds dataset (verbatim from rf-tools-pwa rssi)', () {
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

    test('"good" RSSI band floor is -50 to -67 dBm and grades good', () {
      final SignalBand good = SignalThresholdsScreen.kSignalBands
          .firstWhere((SignalBand b) => b.label == 'Good');
      expect(good.range, '-50 to -67');
      expect(good.grade, SignalGrade.good);
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
}
