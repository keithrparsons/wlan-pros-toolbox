// WifiVsInternetScreen — widget smoke tests.
//
// Drives the screen through its injection seams (a Wi-Fi source + fake
// adapter/bridge, a MockQualityClient with no network) so no real platform
// channel or socket is touched. Covers: renders with the Run button; a full
// macOS run produces a verdict card + both data sections + the verbatim
// footnote; the unknown-rate (iOS, no Shortcut payload) path; the web fallback;
// and a 320px layout with no overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_vs_internet_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

ConnectedAp _macSample() => ConnectedAp.fromWifiInfo(
  WifiInfo(
    interfaceName: 'en0',
    ssid: 'KeithNet',
    bssid: 'a4:83:e7:00:11:22',
    rssiDbm: -50,
    noiseDbm: -95,
    snrDb: 45,
    txRateMbps: 866,
    phyMode: '802.11ax',
    channel: 36,
    channelWidthMhz: 80,
    band: '5 GHz',
    countryCode: 'US',
    hardwareAddress: 'a4:83:e7:aa:bb:cc',
    poweredOn: true,
    locationAuthorized: true,
  ),
);

class _FakeMacAdapter implements WifiInfoAdapter {
  _FakeMacAdapter();

  @override
  String get platformLabel => 'macOS CoreWLAN';

  @override
  bool get gatesNameBehindPermission => true;

  @override
  Future<ConnectedAp> fetch() async => _macSample();

  @override
  Future<bool> requestNamePermission() async => true;

  @override
  Future<bool> currentNameAuthorization() async => true;
}

/// iOS bridge that never delivered a payload — readLatest returns null, so the
/// link is unknown and the engine takes its wifiUnknown path.
class _NoPayloadBridge implements WiFiDetailsBridge {
  @override
  Future<bool> hasEverReceivedPayload() async => false;
  @override
  Future<WiFiDetails?> readLatest() async => null;
  @override
  Future<bool> isMonitoringActive() async => false;
  @override
  Future<void> setMonitoringActive(bool active) async {}
  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
}

/// A [QualityClient] that counts how many times [measure] is subscribed,
/// proving the AppBar Refresh re-runs the SAME check (it re-invokes the screen's
/// one [_run] handler, which re-subscribes this client). A small first-event
/// delay keeps the in-progress state observable across a finite pump; no
/// network I/O.
class _CountingQualityClient implements QualityClient {
  _CountingQualityClient(this.scriptedResult);

  final QualityResult scriptedResult;
  QualityResult? _lastResult;

  /// Number of times the screen has started a run against this client.
  int measureCount = 0;

  @override
  bool get isAvailable => true;

  @override
  QualityResult? get lastResult => _lastResult;

  @override
  Stream<QualityProgress> measure() async* {
    measureCount++;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    yield const QualityProgress(QualityPhase.latency, 0.25);
    yield const QualityProgress(QualityPhase.download, 0.5);
    yield const QualityProgress(QualityPhase.upload, 0.75);
    _lastResult = scriptedResult;
    yield const QualityProgress(QualityPhase.complete, 1.0);
  }
}

/// A net_quality result graded marginal so a finite link produces a
/// localizing verdict rather than the grade-gated "Both healthy".
QualityResult _marginalInternet() => QualityResult(
  source: QualitySource.mock,
  measuredAt: DateTime.utc(2026, 1, 1),
  metrics: const <QualityMetric>[
    QualityMetric(
      id: MetricIds.latency,
      label: 'Latency',
      value: 60,
      unit: 'ms',
      grade: QualityGrade.fair,
    ),
    QualityMetric(
      id: MetricIds.jitter,
      label: 'Jitter',
      value: 8,
      unit: 'ms',
      grade: QualityGrade.fair,
    ),
    QualityMetric(
      id: MetricIds.loss,
      label: 'Loss',
      value: 1,
      unit: '%',
      grade: QualityGrade.fair,
    ),
    QualityMetric(
      id: MetricIds.download,
      label: 'Download',
      value: 60,
      unit: 'Mbps',
      grade: QualityGrade.fair,
    ),
    QualityMetric(
      id: MetricIds.upload,
      label: 'Upload',
      value: 20,
      unit: 'Mbps',
      grade: QualityGrade.fair,
    ),
    QualityMetric(
      id: MetricIds.responsiveness,
      label: 'Responsiveness',
      value: 300,
      unit: 'RPM',
      grade: QualityGrade.fair,
    ),
  ],
);

void main() {
  Widget host(Widget child, {Size? size}) => MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(size: size ?? const Size(390, 844)),
      child: child,
    ),
  );

  testWidgets('renders the intro card with a Run Check button', (tester) async {
    await tester.pumpWidget(
      host(
        WifiVsInternetScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(),
          qualityClient: MockQualityClient(scriptedResult: _marginalInternet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Run Check'), findsOneWidget);
    expect(find.text('Wi-Fi vs Internet'), findsOneWidget);
  });

  testWidgets(
    'a full run renders the verdict card, both sections, and footnote',
    (tester) async {
      await tester.pumpWidget(
        host(
          WifiVsInternetScreen(
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _FakeMacAdapter(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run Check'));
      await tester.pumpAndSettle();

      // Verdict: macOS Tx-only 866 → usable 476.3; marginal internet avg 40 →
      // ratio ≈ 0.084 → upstream.
      expect(find.text("It's upstream — not your Wi-Fi"), findsOneWidget);

      // Both data sections render.
      expect(find.text('Your Wi-Fi link'), findsOneWidget);
      expect(find.text('Your internet'), findsOneWidget);

      // macOS does not report Rx — the honest per-platform note shows.
      expect(find.text('Not reported on this platform'), findsOneWidget);

      // The verbatim method-disclosure footnote is present.
      expect(find.text(kWifiVsInternetFootnote), findsOneWidget);
    },
  );

  testWidgets('iOS with no Shortcut payload takes the unknown-rate path', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        WifiVsInternetScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: _NoPayloadBridge(),
          qualityClient: MockQualityClient(scriptedResult: _marginalInternet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Check'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi link not measured'), findsOneWidget);
  });

  testWidgets('web source shows the download-the-app fallback', (tester) async {
    await tester.pumpWidget(
      host(const WifiVsInternetScreen(sourceOverride: WifiInfoSource.web)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NetworkUnavailableView), findsOneWidget);
  });

  testWidgets(
    'AppBar Refresh re-runs the same check and is disabled while running',
    (tester) async {
      final _CountingQualityClient quality =
          _CountingQualityClient(_marginalInternet());
      await tester.pumpWidget(
        host(
          WifiVsInternetScreen(
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _FakeMacAdapter(),
            qualityClient: quality,
          ),
        ),
      );

      // No Refresh before the first verdict — the in-card Run button is the
      // first-run affordance.
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.refresh), findsNothing);

      // First run via the in-card button.
      await tester.tap(find.text('Run Check'));
      await tester.pumpAndSettle();
      expect(quality.measureCount, 1);

      // Refresh now appears in the AppBar with the §a11y label.
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.bySemanticsLabel('Run the test again'), findsOneWidget);

      // Tap Refresh: a single pump lands on the in-progress state — the refresh
      // IconButton is gone (swapped for the spinner) so the check can't be
      // double-fired, and the second run has begun.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // The re-run settles back to a verdict and the Refresh control restores.
      await tester.pumpAndSettle();
      expect(quality.measureCount, 2);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('Your Wi-Fi link'), findsOneWidget);
    },
  );

  testWidgets('no RenderFlex overflow at 320px after a full run', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        WifiVsInternetScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(),
          qualityClient: MockQualityClient(scriptedResult: _marginalInternet()),
        ),
        size: const Size(320, 700),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Check'));
    await tester.pumpAndSettle();
    // tester.takeException() returns the overflow assertion if any RenderFlex
    // overflowed during layout at 320px.
    expect(tester.takeException(), isNull);
  });
}
