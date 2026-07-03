// Render-proof capture for the 3-tier Strong/Moderate/Weak axis status (NOT a
// golden test). Writes PNG snapshots of the real TestMyConnectionScreen hero —
// the two per-axis chips — to the myPKA Deliverables folder so Vera (and Keith)
// can eyeball the new Strong (success/green) / Moderate (warning/amber) / Weak
// (danger/red) / Couldn't-check (neutral) chips on BOTH axes, in BOTH themes,
// without a device build.
//
// Each scenario drives the production screen through its injection seams (a
// Wi-Fi source + fake adapter/bridge whose negotiated link rate sets the Wi-Fi
// usable capacity tier, and a MockQualityClient whose scripted down/up sets the
// internet tier). No real platform channel, socket, or poll timer is touched.
//
// Tiers are absolute (Keith, 2026-06-07): usable Wi-Fi = 0.55 × avg(Tx,Rx);
// internet = avg(down,up); each bucketed > 250 Strong / 100-250 Moderate /
// < 100 Weak / unmeasured Unknown.
//
// This is a capture utility, not a regression gate. Run it explicitly:
//   flutter test test/screens/tools/network/tmc_3tier_render.dart
// Renders use the production theme + the bundled typefaces loaded by
// flutter_test_config.dart, so the PNGs reflect shipping pixels.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:net_quality/net_quality.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/Documents/myPKA/Deliverables/2026-06-07-tmc-3tier-renders';

// --- Wi-Fi sources, one per Wi-Fi tier (link rate sets the usable capacity) ---

/// macOS adapter at a chosen Tx rate (Rx not exposed on public CoreWLAN, so
/// usable = 0.55 × Tx). Tx 1000 → usable 550 (Strong); Tx 330 → usable 181.5
/// (Moderate); Tx 30 → usable 16.5 (Weak).
class _MacLinkAdapter implements WifiInfoAdapter {
  _MacLinkAdapter(this.txRateMbps);
  final double txRateMbps;

  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => ConnectedAp.fromWifiInfo(
        WifiInfo(
          interfaceName: 'en0',
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
          rssiDbm: -55,
          noiseDbm: -92,
          snrDb: 37,
          txRateMbps: txRateMbps,
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
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// macOS adapter that reports NO link rate (Tx 0) → usable Wi-Fi unmeasured →
/// the Wi-Fi chip is the honest "Couldn't check" (GL-005). Models the
/// platform/permission case where the link could not be read.
class _NoLinkAdapter implements WifiInfoAdapter {
  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => ConnectedAp.fromWifiInfo(
        WifiInfo(
          interfaceName: 'en0',
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
          rssiDbm: -55,
          noiseDbm: -92,
          snrDb: 37,
          txRateMbps: 0, // no negotiated rate → wifiUnknown path
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
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

// --- Internet results, one per internet tier (avg down/up sets the tier) ---

QualityResult _internet({
  required double? down,
  required double? up,
  QualityGrade grade = QualityGrade.fair,
}) =>
    QualityResult(
      source: QualitySource.mock,
      measuredAt: DateTime.utc(2026, 1, 1),
      metrics: <QualityMetric>[
        const QualityMetric(
          id: MetricIds.latency,
          label: 'Latency',
          value: 18,
          unit: 'ms',
          grade: QualityGrade.good,
        ),
        const QualityMetric(
          id: MetricIds.loss,
          label: 'Loss',
          value: 0,
          unit: '%',
          grade: QualityGrade.good,
        ),
        QualityMetric(
          id: MetricIds.download,
          label: 'Download',
          value: down,
          unit: 'Mbps',
          grade: down == null ? QualityGrade.unavailable : grade,
        ),
        QualityMetric(
          id: MetricIds.upload,
          label: 'Upload',
          value: up,
          unit: 'Mbps',
          grade: up == null ? QualityGrade.unavailable : grade,
        ),
      ],
    );

/// One render scenario: a stable filename slug plus the Wi-Fi source and the
/// internet result that together pin the two chip tiers.
typedef _Scenario = ({
  String slug,
  WifiInfoAdapter adapter,
  QualityResult internet,
});

final List<_Scenario> _scenarios = <_Scenario>[
  // Strong / Strong — usable 550 (Tx 1000), internet download 400 (Strong).
  (
    slug: 'wifi-strong_internet-strong',
    adapter: _MacLinkAdapter(1000),
    internet: _internet(down: 400, up: 200, grade: QualityGrade.excellent),
  ),
  // Moderate / Moderate — usable 181.5 (Tx 330), internet download 200 (Moderate).
  (
    slug: 'wifi-moderate_internet-moderate',
    adapter: _MacLinkAdapter(330),
    internet: _internet(down: 200, up: 100),
  ),
  // Weak / Weak — usable 16.5 (Tx 30), internet download 60 (Weak).
  (
    slug: 'wifi-weak_internet-weak',
    adapter: _MacLinkAdapter(30),
    internet: _internet(down: 60, up: 20),
  ),
  // Strong / Weak — the mixed case (usable 550, internet download 60, Weak): the
  // lower tier (internet, Weak) is the limiter the conclusion sentence names.
  (
    slug: 'wifi-strong_internet-weak',
    adapter: _MacLinkAdapter(1000),
    internet: _internet(down: 60, up: 20),
  ),
  // Couldn't check / Moderate — no link rate (Tx 0 → wifiUnknown), internet
  // download 200 measured. Proves the honest neutral Wi-Fi chip beside a real tier.
  (
    slug: 'wifi-unknown_internet-moderate',
    adapter: _NoLinkAdapter(),
    internet: _internet(down: 200, up: 100),
  ),
];

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  final RenderRepaintBoundary boundary = boundaryKey.currentContext!
      .findRenderObject()! as RenderRepaintBoundary;
  // The image encode must run on the real event loop, not the fake test zone.
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final File out = File('$_outDir/$filename');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _renderScenario(
  WidgetTester tester,
  _Scenario s,
  ThemeData theme,
  String themeName,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final GlobalKey boundaryKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 900),
            textScaler: TextScaler.linear(1.0),
          ),
          child: TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: s.adapter,
            qualityClient: MockQualityClient(scriptedResult: s.internet),
            nowOverride: () => DateTime.utc(2026, 6, 7, 14, 30),
          ),
        ),
      ),
    ),
  );

  // Run the check, then settle the result so the hero + chips are painted.
  await tester.pumpAndSettle();
  await tester.tap(find.text('Check My Connection'));
  await tester.pumpAndSettle();

  await _capture(tester, boundaryKey, 'tmc-3tier_${s.slug}_$themeName.png');
}

void main() {
  for (final _Scenario s in _scenarios) {
    testWidgets('render dark: ${s.slug}', (tester) async {
      await _renderScenario(tester, s, AppTheme.dark(), 'dark');
    });
    testWidgets('render light: ${s.slug}', (tester) async {
      await _renderScenario(tester, s, AppTheme.light(), 'light');
    });
  }
}
