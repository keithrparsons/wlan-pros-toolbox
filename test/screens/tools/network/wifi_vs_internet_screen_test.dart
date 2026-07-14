// Wi-Fi vs Internet — redirect + absorbed-technical-section tests (Wave 4).
//
// The standalone `wifi-vs-internet` screen was merged into Test My Connection on
// 2026-06-04: its full pro depth moved into the merged screen's "Wi-Fi vs
// Internet" technical section, and the `/tools/wifi-vs-internet` route redirects
// to the merged screen. In the v1.1 "show more" pass (2026-06-05) the "See the
// details" disclosure was removed and that technical section is now ALWAYS
// rendered. These tests prove nothing the pro tool showed was lost — the verdict
// line, both data sub-cards, and the verbatim methodology footnote all survive
// the merge and render once a check is run.
//
// Live sampling is disabled here (enableLiveSampling: false) so no poll timer
// ticks; the live sparkline card is covered in test_my_connection_screen_test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
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
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// iOS bridge that never delivered a payload — readLatest returns null, so the
/// link is unknown and the engine takes its wifiUnknown path.
class _NoPayloadBridge implements WiFiDetailsBridge {
  @override
  Future<bool> consumeShortcutMissing() async => false;
  @override
  Future<void> markSetupInitiated() async {}
  @override
  Future<bool> hasInitiatedSetup() async => false;
  @override
  Future<bool> isShortcutsAppInstalled() async => true;
  @override
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;
  @override
  Future<bool> hasEverReceivedPayload() async => false;
  @override
  Future<DateTime?> payloadReceivedAt() async => null;
  @override
  Future<WiFiDetails?> readLatest() async => null;
  @override
  Future<bool> isMonitoringActive() async => false;
  @override
  Future<void> setMonitoringActive(bool active) async {}
  @override
  Future<void> resetMonitoringColdStart() async {}
  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Future<bool> runShortcutOneShot(String name) async => true;
  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
}

/// A net_quality result graded marginal so a finite link produces a localizing
/// verdict rather than the grade-gated "Both healthy".
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

  Future<void> runCheck(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check My Connection'));
    await tester.pumpAndSettle();
  }

  test('the /tools/wifi-vs-internet route is preserved as a redirect', () {
    // The deep link survives the merge — a saved reference still resolves.
    expect(AppRouter.routes.containsKey(AppRouter.wifiVsInternet), isTrue);
    expect(AppRouter.wifiVsInternet, '/tools/wifi-vs-internet');
  });

  testWidgets(
    'a full macOS run shows the absorbed "Wi-Fi vs Internet" section ALWAYS: '
    'verdict line, both sub-cards, and the verbatim footnote',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            startExpanded: true,
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _FakeMacAdapter(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // The named concept survives the merge as the section heading.
      expect(find.text('Wi-Fi vs Internet'), findsOneWidget);

      // The pro verdict line: macOS Tx-only 866 → usable 476.3; marginal
      // internet download 60 → ratio ≈ 0.126 → upstream.
      expect(find.text("It's upstream, not your Wi-Fi"), findsOneWidget);

      // Both data sub-cards render.
      expect(find.text('Your Wi-Fi link'), findsOneWidget);
      expect(find.text('Your internet'), findsOneWidget);

      // macOS public CoreWLAN does not expose Rx — the honest, KNOWN-platform-
      // limit note shows ("Not exposed on macOS"), not a glitch.
      expect(find.text('Not exposed on macOS'), findsOneWidget);

      // The verbatim method-disclosure footnote is present.
      expect(find.text(kWifiVsInternetFootnote), findsOneWidget);
    },
  );

  testWidgets(
    'the technical section is ALWAYS rendered — no "See the details" disclosure '
    'and no tap required (v1.1 show-more pass)',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _FakeMacAdapter(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // The disclosure row is gone; the absorbed depth is in the tree at once.
      expect(find.text('See the details'), findsNothing);
      expect(find.text('Your Wi-Fi link'), findsOneWidget);
      expect(find.text('Your internet'), findsOneWidget);
      expect(find.text(kWifiVsInternetFootnote), findsOneWidget);
    },
  );

  testWidgets(
    'iOS with no Shortcut payload still computes (link unknown → Couldn\'t check)',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            startExpanded: true,
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _NoPayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // Link unread → the Wi-Fi axis honestly reports "Couldn't check", and the
      // absorbed technical verdict line shows the engine's wifiUnknown headline.
      expect(find.text("Couldn't check"), findsWidgets);
      expect(find.text('Wi-Fi link not measured'), findsOneWidget);
    },
  );

  testWidgets('web source shows the download-the-app fallback', (tester) async {
    await tester.pumpWidget(
      host(
        const TestMyConnectionScreen(
          enableLiveSampling: false,
          sourceOverride: WifiInfoSource.web,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NetworkUnavailableView), findsOneWidget);
  });

  testWidgets('no RenderFlex overflow at 320px after a full expanded run', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        TestMyConnectionScreen(
          startExpanded: true,
          enableLiveSampling: false,
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: _FakeMacAdapter(),
          qualityClient: MockQualityClient(scriptedResult: _marginalInternet()),
        ),
        size: const Size(320, 700),
      ),
    );
    await runCheck(tester);
    expect(tester.takeException(), isNull);
  });
}
