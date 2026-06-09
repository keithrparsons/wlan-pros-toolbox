// WifiLiveTrend — scoped widget + unit tests for the H2 live RSSI/Tx-rate trend.
//
// Drives the widget directly over a hand-built WifiTimeSeries (no platform, no
// socket, no Shortcut), so it is fully deterministic. Covers:
//   * TrendStats math over a window with gaps (nulls skipped, never averaged
//     toward 0; current reflects the latest PRESENT sample, or null when the
//     latest sample itself is a gap);
//   * the chart renders (fl_chart LineChart present) once samples exist;
//   * the current/min/avg/max summary renders and updates between builds;
//   * graceful degradation — Rx rate not exposed by the platform shows the
//     honest "not reported" reason, NOT a chart and NOT a fabricated line;
//   * a field whose whole window is null shows the honest waiting state.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_live_trend.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_time_series.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Builds a series from per-field windows (oldest → newest). Each list must be
/// the same length; index i is one sample. A null means that field was absent
/// in that sample (a gap).
WifiTimeSeries _seriesFrom({
  required List<int?> rssi,
  required List<double?> tx,
  List<double?>? rx,
}) {
  final WifiTimeSeries s = WifiTimeSeries(capacity: 60);
  for (int i = 0; i < rssi.length; i++) {
    s.add(ConnectedAp(
      rssiDbm: rssi[i],
      txRateMbps: tx[i],
      rxRateMbps: rx == null ? null : rx[i],
      rxRateAvailable: rx != null,
    ));
  }
  return s;
}

Widget _host(Widget child, {Size size = const Size(390, 844)}) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: size),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

void main() {
  group('TrendStats', () {
    test('computes current/min/avg/max over present samples', () {
      final TrendStats s =
          TrendStats.fromWindow(<double?>[-60, -55, -50, -52]);
      expect(s.hasData, isTrue);
      expect(s.sampleCount, 4);
      expect(s.current, -52);
      expect(s.min, -60);
      expect(s.max, -50);
      expect(s.avg, closeTo((-60 - 55 - 50 - 52) / 4, 1e-9));
    });

    test('skips gaps — a null never pulls the average toward 0', () {
      final TrendStats s =
          TrendStats.fromWindow(<double?>[100, null, 200, null, 300]);
      expect(s.sampleCount, 3);
      expect(s.avg, closeTo(200, 1e-9)); // (100+200+300)/3, NOT /5
      expect(s.min, 100);
      expect(s.max, 300);
      // Latest sample is present → current is the last present value.
      expect(s.current, 300);
    });

    test('current is null when the LATEST sample is a gap', () {
      final TrendStats s = TrendStats.fromWindow(<double?>[-50, -55, null]);
      expect(s.hasData, isTrue); // earlier samples were present
      expect(s.current, isNull); // but "now" is a gap
      expect(s.min, -55);
      expect(s.max, -50);
    });

    test('all-null window has no data', () {
      final TrendStats s = TrendStats.fromWindow(<double?>[null, null]);
      expect(s.hasData, isFalse);
      expect(s.current, isNull);
      expect(s.avg, isNull);
    });

    test('empty window has no data', () {
      final TrendStats s = TrendStats.fromWindow(<double?>[]);
      expect(s.hasData, isFalse);
    });
  });

  group('WifiLiveTrend widget', () {
    testWidgets('renders charts + current/min/avg/max once samples exist',
        (tester) async {
      final WifiTimeSeries series = _seriesFrom(
        rssi: <int?>[-60, -58, -55, -57],
        tx: <double?>[300, 350, 480, 480],
        rx: <double?>[200, 240, 360, 360],
      );
      await tester.pumpWidget(_host(WifiLiveTrend(
        series: series,
        latest: const ConnectedAp(
          rssiDbm: -57,
          txRateMbps: 480,
          rxRateMbps: 360,
          rxRateAvailable: true,
        ),
        platformLabel: 'iOS Live',
      )));

      expect(find.text('Live trend'), findsOneWidget);
      // The summary stat labels appear once per charted field (RSSI, Tx, Rx) ×4.
      expect(find.text('current'), findsNWidgets(3));
      expect(find.text('min'), findsNWidgets(3));
      expect(find.text('avg'), findsNWidgets(3));
      expect(find.text('max'), findsNWidgets(3));
      // All three fields chart (RSSI, Tx rate, Rx rate available here).
      expect(find.byType(LineChart), findsNWidgets(3));
    });

    testWidgets('Rx not exposed by platform → honest reason, no Rx chart',
        (tester) async {
      // macOS public CoreWLAN: rxRateAvailable false. RSSI + Tx still chart.
      final WifiTimeSeries series = _seriesFrom(
        rssi: <int?>[-50, -52, -49],
        tx: <double?>[866, 866, 780],
        // rx omitted → all null AND rxRateAvailable false on the latest reading.
      );
      await tester.pumpWidget(_host(WifiLiveTrend(
        series: series,
        latest: const ConnectedAp(
          rssiDbm: -49,
          txRateMbps: 780,
          // ignore: avoid_redundant_argument_values
          rxRateAvailable: false,
        ),
        platformLabel: 'macOS CoreWLAN',
      )));

      // Graceful degradation: the honest reason, NOT a fabricated flat line.
      expect(
        find.text('Rx rate is not reported by macOS CoreWLAN.'),
        findsOneWidget,
      );
      // Only RSSI + Tx chart; Rx shows the reason panel instead.
      expect(find.byType(LineChart), findsNWidgets(2));
    });

    testWidgets('summary updates when a new sample arrives', (tester) async {
      WifiTimeSeries series = _seriesFrom(
        rssi: <int?>[-70],
        tx: <double?>[100],
        rx: <double?>[80],
      );
      ConnectedAp latest = const ConnectedAp(
        rssiDbm: -70,
        txRateMbps: 100,
        rxRateMbps: 80,
        rxRateAvailable: true,
      );

      Widget build() => _host(WifiLiveTrend(
            series: series,
            latest: latest,
            platformLabel: 'iOS Live',
          ));

      await tester.pumpWidget(build());
      // The accessible RSSI summary reflects the initial single sample.
      expect(
        find.bySemanticsLabel(RegExp(r'RSSI trend.*current -70 dBm')),
        findsOneWidget,
      );

      // A new, stronger sample arrives.
      series = _seriesFrom(
        rssi: <int?>[-70, -54],
        tx: <double?>[100, 240],
        rx: <double?>[80, 200],
      );
      latest = const ConnectedAp(
        rssiDbm: -54,
        txRateMbps: 240,
        rxRateMbps: 200,
        rxRateAvailable: true,
      );
      await tester.pumpWidget(build());
      await tester.pump();

      // The accessible RSSI summary advanced to the new latest sample, with the
      // min retained from the earlier (weaker) reading — proof the window rolls.
      expect(
        find.bySemanticsLabel(
          RegExp(r'RSSI trend.*current -54 dBm.*minimum -70 dBm.*maximum -54 dBm'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('field with an all-null window shows the waiting state',
        (tester) async {
      // RSSI present, Tx present, but Rx available yet every sample omitted it
      // (a per-reading miss on a platform that CAN report Rx) → waiting, not 0.
      final WifiTimeSeries series = _seriesFrom(
        rssi: <int?>[-60, -61],
        tx: <double?>[120, 130],
        rx: <double?>[null, null],
      );
      await tester.pumpWidget(_host(WifiLiveTrend(
        series: series,
        latest: const ConnectedAp(
          rssiDbm: -61,
          txRateMbps: 130,
          rxRateAvailable: true, // platform CAN report it; this run had none
        ),
        platformLabel: 'iOS Live',
      )));

      expect(find.text('Waiting for the first reading…'), findsOneWidget);
      // RSSI + Tx chart; Rx waits (no fabricated line).
      expect(find.byType(LineChart), findsNWidgets(2));
    });
  });
}
