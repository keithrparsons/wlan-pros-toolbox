// Render-proof capture for the SAME-TIER HERO sentence (NOT a golden test).
// Writes PNG snapshots of the real TestMyConnectionScreen hero — where both
// absolute axis chips land on the SAME tier and the hero is therefore worded by
// MARGIN ("Both sides are <tier>. They’re about the same speed." / "...Your
// <Wi-Fi|internet> is slightly ahead.") — to the myPKA Deliverables folder so
// Vera (and Keith) can eyeball the new wording beside two equal chips, in BOTH
// themes, without a device build.
//
// Each scenario drives the production screen through its injection seams (a
// macOS adapter whose Tx rate sets the Wi-Fi usable-capacity tier, and a
// MockQualityClient whose scripted down/up sets the internet tier). No real
// platform channel, socket, or poll timer is touched.
//
// Tiers are absolute (Keith, 2026-06-07): usable Wi-Fi = 0.55 × Tx (Rx not
// exposed on public CoreWLAN); internet = avg(down,up); bucketed > 250 Strong /
// 100-250 Moderate / < 100 Weak. Margin reuses the +/-10% comparison band.
//
// This is a capture utility, not a regression gate. Run it explicitly:
//   flutter test test/screens/tools/network/tmc_sametier_render.dart

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
    '/Users/keithparsons/Documents/myPKA/Deliverables/2026-06-07-tmc-sametier-renders';

/// macOS adapter at a chosen Tx rate → usable Wi-Fi = 0.55 × Tx.
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

QualityResult _internet({
  required double down,
  required double up,
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
          grade: QualityGrade.fair,
        ),
        QualityMetric(
          id: MetricIds.upload,
          label: 'Upload',
          value: up,
          unit: 'Mbps',
          grade: QualityGrade.fair,
        ),
      ],
    );

typedef _Scenario = ({
  String slug,
  WifiInfoAdapter adapter,
  QualityResult internet,
});

final List<_Scenario> _scenarios = <_Scenario>[
  // Moderate / Moderate, Wi-Fi slightly ahead — Vera's example case.
  // Tx 360 → usable 198; internet 200/100 → avg 150; margin +32%.
  (
    slug: 'moderate-moderate_wifi-ahead',
    adapter: _MacLinkAdapter(360),
    internet: _internet(down: 200, up: 100),
  ),
  // Moderate / Moderate, about the same — Tx 360 → usable 198; 240/160 → 200.
  (
    slug: 'moderate-moderate_about-same',
    adapter: _MacLinkAdapter(360),
    internet: _internet(down: 240, up: 160),
  ),
  // Strong / Strong, about the same — Tx 720 → usable 396; 440/360 → avg 400.
  (
    slug: 'strong-strong_about-same',
    adapter: _MacLinkAdapter(720),
    internet: _internet(down: 440, up: 360),
  ),
  // Weak / Weak, about the same — Tx 120 → usable 66; 80/40 → avg 60.
  (
    slug: 'weak-weak_about-same',
    adapter: _MacLinkAdapter(120),
    internet: _internet(down: 80, up: 40),
  ),
];

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  final RenderRepaintBoundary boundary = boundaryKey.currentContext!
      .findRenderObject()! as RenderRepaintBoundary;
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

  await tester.pumpAndSettle();
  await tester.tap(find.text('Check My Connection'));
  await tester.pumpAndSettle();

  await _capture(tester, boundaryKey, 'tmc-sametier_${s.slug}_$themeName.png');
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
